#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly BLINDOU_REPOSITORY="${1:-$(cd "${REPOSITORY_ROOT}/.." && pwd)/blindou}"
readonly VERIFIER="${REPOSITORY_ROOT}/operations/remote/blindou-release-verify.py"

fail() {
  printf '[verify-blindou-release-contract] ERRO: %s\n' "$*" >&2
  exit 1
}

python_command=''
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 \
      && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
    python_command="$candidate"
    break
  fi
done
[[ -n "$python_command" ]] || fail 'Python com PyYAML e obrigatorio'
[[ -d "${BLINDOU_REPOSITORY}/.git" ]] || fail 'repositorio Blindou ausente'

temporary_dir="$(mktemp -d)"
cleanup() {
  rm -rf -- "$temporary_dir"
}
trap cleanup EXIT

release_id="$(git -C "$BLINDOU_REPOSITORY" rev-parse HEAD)"
digest_a="$(printf 'a%.0s' {1..64})"
digest_b="$(printf 'b%.0s' {1..64})"
digest_c="$(printf 'c%.0s' {1..64})"
digest_d="$(printf 'd%.0s' {1..64})"
digest_e="$(printf 'e%.0s' {1..64})"

"${BLINDOU_REPOSITORY}/deploy/scripts/render-physical-k3s.sh" \
  --release "$release_id" \
  --backend-image "registry.invalid/blindou/backend@sha256:${digest_a}" \
  --redirector-image "registry.invalid/blindou/redirector@sha256:${digest_b}" \
  --nats-image "registry.invalid/library/nats@sha256:${digest_c}" \
  --redis-image "registry.invalid/library/redis@sha256:${digest_d}" \
  --cloudflared-image "registry.invalid/cloudflare/cloudflared@sha256:${digest_e}" \
  --postgres-host-cidr 10.42.0.1/32 \
  --output-dir "${temporary_dir}/rendered"

create_archive() {
  local source_dir="$1"
  local archive="$2"
  tar -czf "$archive" -C "$source_dir" \
    00-platform.yaml 10-services.yaml 20-nats-config.yaml \
    30-network-policies.yaml 40-workloads.yaml 60-cloudflared.yaml workers
}

create_archive "${temporary_dir}/rendered" "${temporary_dir}/rendered.tar.gz"
archive_sha="$(sha256sum "${temporary_dir}/rendered.tar.gz" | awk '{print $1}')"
"$python_command" "$VERIFIER" \
  "${temporary_dir}/rendered.tar.gz" "${temporary_dir}/verified" \
  "$release_id" "$archive_sha"

sed -i '0,/type: ClusterIP/s//type: NodePort/' \
  "${temporary_dir}/rendered/10-services.yaml"
create_archive "${temporary_dir}/rendered" "${temporary_dir}/tampered.tar.gz"
tampered_sha="$(sha256sum "${temporary_dir}/tampered.tar.gz" | awk '{print $1}')"
if "$python_command" "$VERIFIER" \
    "${temporary_dir}/tampered.tar.gz" "${temporary_dir}/tampered-verified" \
    "$release_id" "$tampered_sha" >/dev/null 2>&1; then
  fail 'bundle adulterado com NodePort foi aceito'
fi

printf '%s\n' 'blindou_release_contract=passed tampered_bundle=rejected'
