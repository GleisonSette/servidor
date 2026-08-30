#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
umask 077

fail() {
  printf '[dre-image-publish] ERRO: %s\n' "$*" >&2
  exit 1
}

[[ "$#" -eq 5 ]] \
  || fail 'uso fechado: REMOTE_ROOT SOURCE_REVISION REGCTL_SHA256 SYFT_SHA256 TRIVY_SHA256'
readonly remote_root="$1"
readonly source_revision="$2"
readonly regctl_sha256="$3"
readonly syft_sha256="$4"
readonly trivy_sha256="$5"
readonly output_directory="${remote_root}/output"
readonly evidence_directory="${remote_root}/evidence"
readonly regctl="${remote_root}/regctl"
readonly syft="${remote_root}/syft"
readonly trivy="${remote_root}/trivy"
readonly cache_directory="${remote_root}/trivy-cache"
readonly tag_suffix="git-${source_revision:0:12}"

[[ "${EUID}" -ne 0 ]] || fail 'publicação não deve executar como root'
[[ "$(id -un)" == apiadmin ]] || fail 'usuário inesperado'
[[ "$(hostname)" == apiwpp ]] || fail 'hostname inesperado'
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || fail 'revisão-fonte inválida'
for digest in "$regctl_sha256" "$syft_sha256" "$trivy_sha256"; do
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail 'SHA-256 de ferramenta inválido'
done
[[ "$remote_root" == \
  "/home/apiadmin/dre-image-build-${source_revision:0:12}-"* ]] \
  || fail 'staging remoto fora do prefixo aprovado'
[[ "$remote_root" =~ ^/home/apiadmin/dre-image-build-[0-9a-f]{12}-[0-9]{8}T[0-9]{6}Z$ ]] \
  || fail 'staging remoto possui formato inválido'

for command in chmod cut date find flock id jq mkdir mktemp mv rm sha256sum \
  stat; do
  command -v "$command" >/dev/null || fail "dependência ausente: ${command}"
done
[[ -d "$output_directory" && ! -L "$output_directory" ]] \
  || fail 'saída do build ausente ou simbólica'
[[ "$(stat -c '%U:%G:%a:%h' "$output_directory")" == \
  'apiadmin:apiadmin:700:2' ]] || fail 'diretório de build inseguro'
[[ ! -e "$evidence_directory" && ! -L "$evidence_directory" ]] \
  || fail 'diretório de evidência já existe'
for tool in "$regctl" "$syft" "$trivy"; do
  [[ -f "$tool" && ! -L "$tool" ]] || fail "ferramenta ausente: ${tool}"
  [[ "$(stat -c '%U:%G:%a:%h' "$tool")" == 'apiadmin:apiadmin:700:1' ]] \
    || fail "ferramenta possui modo inseguro: ${tool}"
done
[[ "$(sha256sum "$regctl" | cut -d' ' -f1)" == "$regctl_sha256" ]] \
  || fail 'SHA-256 do regctl diverge'
[[ "$(sha256sum "$syft" | cut -d' ' -f1)" == "$syft_sha256" ]] \
  || fail 'SHA-256 do Syft diverge'
[[ "$(sha256sum "$trivy" | cut -d' ' -f1)" == "$trivy_sha256" ]] \
  || fail 'SHA-256 do Trivy diverge'

for component in rust postgres validation; do
  archive="${output_directory}/${component}.oci.tar"
  metadata="${output_directory}/${component}.metadata.json"
  for artifact in "$archive" "$metadata"; do
    [[ -s "$artifact" && ! -L "$artifact" ]] \
      || fail "artefato do build ausente: ${artifact}"
    [[ "$(stat -c '%U:%G:%a:%h' "$artifact")" == \
      'apiadmin:apiadmin:600:1' ]] || fail "artefato do build inseguro: ${artifact}"
  done
done
(cd "$output_directory" && sha256sum -c SHA256SUMS >/dev/null)
jq -e --arg revision "$source_revision" \
  '.schema == 1 and .status == "passed" and .source_revision == $revision and .platform == "linux/amd64" and .components == ["rust","postgres","validation"]' \
  "${output_directory}/build-receipt.json" >/dev/null \
  || fail 'recibo do build diverge'

exec 8>"${remote_root}/.publish.lock"
chmod 0600 "${remote_root}/.publish.lock"
flock -n 8 || fail 'outra publicação DRE está em andamento'

temporary="$(mktemp -d /tmp/dre-image-publish.XXXXXX)"
temporary_evidence="${temporary}/evidence"
temporary_home="${temporary}/home"
mkdir -m 0700 "$temporary_evidence" "$temporary_home" \
  "${temporary_evidence}/sbom" "${temporary_evidence}/scan" \
  "${temporary_evidence}/raw" "$cache_directory"
token=''
cleanup() {
  local result="$?"
  trap - EXIT
  token=''
  if [[ -n "$temporary" && -d "$temporary" \
      && "$temporary" == /tmp/dre-image-publish.* ]]; then
    rm -rf --one-file-system -- "$temporary"
  fi
  exit "$result"
}
trap cleanup EXIT

for component in rust postgres validation; do
  archive="${output_directory}/${component}.oci.tar"
  "$syft" scan "oci-archive:${archive}" --quiet \
    --output "spdx-json=${temporary_evidence}/sbom/${component}.spdx.json"
  jq -e '.spdxVersion | startswith("SPDX-2.")' \
    "${temporary_evidence}/sbom/${component}.spdx.json" >/dev/null \
    || fail "SBOM inválido: ${component}"
  jq -e '.packages | type == "array"' \
    "${temporary_evidence}/sbom/${component}.spdx.json" >/dev/null \
    || fail "SBOM sem packages: ${component}"
  "$trivy" image --input "$archive" --scanners vuln \
    --severity HIGH,CRITICAL --exit-code 1 --format json \
    --cache-dir "$cache_directory" \
    --output "${temporary_evidence}/raw/${component}.trivy.json"
  critical="$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' \
    "${temporary_evidence}/raw/${component}.trivy.json")"
  high="$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' \
    "${temporary_evidence}/raw/${component}.trivy.json")"
  [[ "$critical" -eq 0 && "$high" -eq 0 ]] \
    || fail "scan contém vulnerabilidade alta/crítica: ${component}"
done

IFS= read -r token || fail 'credencial GHCR ausente no stdin'
[[ -n "$token" && "${#token}" -le 1024 \
    && "$token" != *$'\r'* && "$token" != *$'\n'* ]] \
  || fail 'credencial GHCR possui formato inválido'
printf '%s\n' "$token" \
  | HOME="$temporary_home" "$regctl" registry login ghcr.io \
      --user GleisonSette --pass-stdin >/dev/null
token=''

declare -A image_names=(
  [rust]='ghcr.io/gleisonsette/dre-app'
  [postgres]='ghcr.io/gleisonsette/dre-postgres'
  [validation]='ghcr.io/gleisonsette/dre-validation-runner'
)
declare -A image_digests=()
for component in rust postgres validation; do
  tag="${image_names[$component]}:${tag_suffix}"
  HOME="$temporary_home" "$regctl" image import "$tag" \
    "${output_directory}/${component}.oci.tar"
  digest="$(HOME="$temporary_home" "$regctl" image digest "$tag")"
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || fail "registry não devolveu digest imutável: ${component}"
  HOME="$temporary_home" "$regctl" image digest \
    --platform linux/amd64 "$tag" >/dev/null \
    || fail "imagem não oferece linux/amd64: ${component}"
  image_digests[$component]="$digest"
done
HOME="$temporary_home" "$regctl" registry logout ghcr.io >/dev/null || true

for component in rust postgres validation; do
  raw="${temporary_evidence}/raw/${component}.trivy.json"
  raw_sha="$(sha256sum "$raw" | cut -d' ' -f1)"
  image="${image_names[$component]}@${image_digests[$component]}"
  jq -n \
    --arg scanner "Trivy 0.72.0 raw-sha256:${raw_sha}" \
    --arg image "$image" \
    '{schema:1,scanner:$scanner,image:$image,platform:"linux/amd64",status:"passed",critical_vulnerabilities:0,high_vulnerabilities:0}' \
    >"${temporary_evidence}/scan/${component}.json"
done

jq -n \
  --arg source_revision "$source_revision" \
  --arg rust_image "${image_names[rust]}@${image_digests[rust]}" \
  --arg postgres_image "${image_names[postgres]}@${image_digests[postgres]}" \
  --arg validation_image "${image_names[validation]}@${image_digests[validation]}" \
  --arg regctl_sha256 "$regctl_sha256" \
  --arg syft_sha256 "$syft_sha256" \
  --arg trivy_sha256 "$trivy_sha256" \
  --arg completed_at_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{schema:1,status:"passed",source_revision:$source_revision,platform:"linux/amd64",images:{rust:$rust_image,postgres:$postgres_image,validation:$validation_image},tools:{regctl:{version:"v0.11.5",sha256:$regctl_sha256},syft:{version:"1.51.0",sha256:$syft_sha256},trivy:{version:"0.72.0",sha256:$trivy_sha256}},completed_at_utc:$completed_at_utc}' \
  >"${temporary_evidence}/publish-receipt.json"

find "$temporary_evidence" -type d -exec chmod 0700 {} +
find "$temporary_evidence" -type f -exec chmod 0600 {} +
mv -- "$temporary_evidence" "$evidence_directory"
printf 'dre_image_publish=passed source_revision=%s receipt=%s\n' \
  "$source_revision" "${evidence_directory}/publish-receipt.json"
