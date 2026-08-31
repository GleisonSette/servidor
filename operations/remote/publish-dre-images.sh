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

for command in chmod cut date find flock id jq mkdir mktemp mv python3 rm \
  sha256sum stat; do
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
temporary_oci="${temporary}/oci"
mkdir -m 0700 "$temporary_evidence" "$temporary_home" \
  "${temporary_evidence}/sbom" "${temporary_evidence}/scan" \
  "${temporary_evidence}/raw" "$temporary_oci"
if [[ -e "$cache_directory" || -L "$cache_directory" ]]; then
  [[ -d "$cache_directory" && ! -L "$cache_directory" \
      && "$(stat -c '%U:%G:%a' "$cache_directory")" == \
        'apiadmin:apiadmin:700' ]] \
    || fail 'cache Trivy preexistente é inseguro'
else
  mkdir -m 0700 "$cache_directory"
fi
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

python3 - "$output_directory" "$temporary_oci" <<'PY'
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import tarfile

output_directory = Path(sys.argv[1])
destination_root = Path(sys.argv[2]).resolve()
components = ("rust", "postgres", "validation")
blob_pattern = re.compile(r"^blobs/sha256/([0-9a-f]{64})$")
allowed_directories = {"blobs", "blobs/sha256"}
required_files = {"index.json", "oci-layout"}
maximum_members = 4096
maximum_file_bytes = 1024 * 1024 * 1024
maximum_total_bytes = 2 * 1024 * 1024 * 1024


def validated_name(raw_name: str) -> str:
    path = PurePosixPath(raw_name)
    normalized = str(path)
    if (
        not raw_name
        or path.is_absolute()
        or normalized != raw_name.rstrip("/")
        or any(part in {"", ".", ".."} for part in path.parts)
    ):
        raise SystemExit(f"caminho inválido no OCI: {raw_name!r}")
    return normalized


for component in components:
    archive = output_directory / f"{component}.oci.tar"
    destination = destination_root / component
    destination.mkdir(mode=0o700)
    names: set[str] = set()
    regular_files: set[str] = set()
    total_bytes = 0
    with tarfile.open(archive, mode="r:") as image:
        members = image.getmembers()
        if not members or len(members) > maximum_members:
            raise SystemExit(f"quantidade de membros OCI inválida: {component}")
        for member in members:
            name = validated_name(member.name)
            if name in names:
                raise SystemExit(f"membro OCI duplicado: {component}:{name}")
            names.add(name)
            if member.isdir():
                if name not in allowed_directories:
                    raise SystemExit(f"diretório OCI inesperado: {component}:{name}")
                continue
            blob_match = blob_pattern.fullmatch(name)
            if not member.isreg() or (
                name not in required_files and blob_match is None
            ):
                raise SystemExit(f"membro OCI inesperado: {component}:{name}")
            if member.size <= 0 or member.size > maximum_file_bytes:
                raise SystemExit(f"tamanho OCI inválido: {component}:{name}")
            total_bytes += member.size
            if total_bytes > maximum_total_bytes:
                raise SystemExit(f"OCI excede o limite total: {component}")

            target = destination.joinpath(*PurePosixPath(name).parts)
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            source = image.extractfile(member)
            if source is None:
                raise SystemExit(f"membro OCI ilegível: {component}:{name}")
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
            flags |= getattr(os, "O_NOFOLLOW", 0)
            descriptor = os.open(target, flags, 0o600)
            digest = hashlib.sha256()
            try:
                with source:
                    while chunk := source.read(1024 * 1024):
                        digest.update(chunk)
                        view = memoryview(chunk)
                        while view:
                            written = os.write(descriptor, view)
                            if written <= 0:
                                raise SystemExit(
                                    f"gravação OCI interrompida: {component}:{name}"
                                )
                            view = view[written:]
                os.fsync(descriptor)
                metadata = os.fstat(descriptor)
                if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                    raise SystemExit(f"alvo OCI inseguro: {component}:{name}")
            finally:
                os.close(descriptor)
            if blob_match is not None and digest.hexdigest() != blob_match.group(1):
                raise SystemExit(f"digest OCI divergente: {component}:{name}")
            regular_files.add(name)

    if not required_files.issubset(regular_files):
        raise SystemExit(f"layout OCI incompleto: {component}")
    layout = json.loads((destination / "oci-layout").read_text(encoding="utf-8"))
    if layout.get("imageLayoutVersion") != "1.0.0":
        raise SystemExit(f"versão do layout OCI inválida: {component}")
    index = json.loads((destination / "index.json").read_text(encoding="utf-8"))
    manifests = index.get("manifests")
    if index.get("schemaVersion") != 2 or not isinstance(manifests, list) or not manifests:
        raise SystemExit(f"índice OCI inválido: {component}")
    for manifest in manifests:
        if not isinstance(manifest, dict):
            raise SystemExit(f"descritor OCI inválido: {component}")
        digest = manifest.get("digest")
        if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise SystemExit(f"digest do índice OCI inválido: {component}")
        if not (destination / "blobs" / "sha256" / digest.removeprefix("sha256:")).is_file():
            raise SystemExit(f"manifesto OCI ausente: {component}")
PY

for component in rust postgres validation; do
  archive="${output_directory}/${component}.oci.tar"
  raw="${temporary_evidence}/raw/${component}.trivy.json"
  "$syft" scan "oci-archive:${archive}" --quiet \
    --output "spdx-json=${temporary_evidence}/sbom/${component}.spdx.json"
  jq -e '.spdxVersion | startswith("SPDX-2.")' \
    "${temporary_evidence}/sbom/${component}.spdx.json" >/dev/null \
    || fail "SBOM inválido: ${component}"
  jq -e '.packages | type == "array"' \
    "${temporary_evidence}/sbom/${component}.spdx.json" >/dev/null \
    || fail "SBOM sem packages: ${component}"
  trivy_result=0
  "$trivy" image --input "${temporary_oci}/${component}" --scanners vuln \
    --severity HIGH,CRITICAL --exit-code 1 --format json \
    --skip-version-check \
    --cache-dir "$cache_directory" \
    --output "$raw" \
    || trivy_result=$?
  [[ -s "$raw" ]] \
    || fail "Trivy não produziu relatório: ${component}"
  critical="$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' \
    "$raw")"
  high="$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' \
    "$raw")"
  if [[ "$critical" -ne 0 || "$high" -ne 0 ]]; then
    finding_count="$(jq '
      [.Results[]?.Vulnerabilities[]?
       | select(.Severity == "HIGH" or .Severity == "CRITICAL")
       | {id:.VulnerabilityID,package:.PkgName,installed:.InstalledVersion,
          fixed:(.FixedVersion // "indisponível"),severity:.Severity,
          status:(.Status // "desconhecido")}]
      | unique_by([.id,.package,.installed,.fixed,.severity])
      | length
    ' "$raw")"
    printf '[dre-image-publish] %s possui %s achado(s) único(s); exibindo no máximo 20:\n' \
      "$component" "$finding_count" >&2
    jq -r '
      [.Results[]?.Vulnerabilities[]?
       | select(.Severity == "HIGH" or .Severity == "CRITICAL")
       | {id:.VulnerabilityID,package:.PkgName,installed:.InstalledVersion,
          fixed:(.FixedVersion // "indisponível"),severity:.Severity,
          status:(.Status // "desconhecido")}]
      | unique_by([.id,.package,.installed,.fixed,.severity])
      | sort_by(.severity,.package,.id)
      | .[:20][]
      | "\(.severity) \(.id) pacote=\(.package) instalado=\(.installed) corrigido=\(.fixed) status=\(.status)"
    ' "$raw" >&2
    fail "scan contém vulnerabilidade alta/crítica: ${component}"
  fi
  [[ "$trivy_result" -eq 0 ]] \
    || fail "Trivy encerrou com erro não classificado: ${component}"
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
