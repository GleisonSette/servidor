#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
umask 077
readonly EXPECTED_HOSTNAME='apiwpp'
readonly SOURCE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SOURCE_DIRECTORY}/../.." && pwd)"
readonly CONTROLLER_SOURCE="${SOURCE_DIRECTORY}/blindou-datactl"
readonly RELEASE_VERIFIER_SOURCE="${SOURCE_DIRECTORY}/blindou-data-release-verify.py"
readonly SECRET_VERIFIER_SOURCE="${SOURCE_DIRECTORY}/blindou-data-secret-verify.py"
readonly GHCR_PULL_VERIFIER_SOURCE="${SOURCE_DIRECTORY}/blindou-data-ghcr-pull-verify.py"
readonly SUDOERS_SOURCE="${SOURCE_DIRECTORY}/blindou-datactl.sudoers"
readonly APPLICATION_POLICY_SOURCE="${REPOSITORY_ROOT}/platform/blindou/20-production-workload-policy.yaml"
readonly DATA_PLATFORM_SOURCE="${REPOSITORY_ROOT}/platform/blindou-data"
readonly DATA_PLATFORM_VERIFIER="${SOURCE_DIRECTORY}/verify-blindou-data-artifacts.py"
readonly CONTROLLER_TARGET='/usr/local/sbin/blindou-datactl'
readonly LIBRARY_TARGET='/usr/local/lib/blindou-data'
readonly SUDOERS_TARGET='/etc/sudoers.d/blindou-datactl'

fail() {
  printf '[bootstrap-blindou-datactl] ERRO: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'
[[ "$(hostname)" == "$EXPECTED_HOSTNAME" ]] || fail 'hostname inesperado'
for source in "$CONTROLLER_SOURCE" "$RELEASE_VERIFIER_SOURCE" \
  "$SECRET_VERIFIER_SOURCE" "$GHCR_PULL_VERIFIER_SOURCE" "$SUDOERS_SOURCE" "$APPLICATION_POLICY_SOURCE" \
  "$DATA_PLATFORM_SOURCE/00-namespace.yaml" "$DATA_PLATFORM_SOURCE/10-quarantine.yaml" \
  "$DATA_PLATFORM_SOURCE/20-workload-policy.yaml" "$DATA_PLATFORM_SOURCE/kustomization.yaml" \
  "$DATA_PLATFORM_VERIFIER"; do
  [[ -f "$source" && ! -L "$source" ]] || fail "fonte ausente ou simbólica: ${source}"
done
bash -n "$CONTROLLER_SOURCE"
python3 - "$RELEASE_VERIFIER_SOURCE" "$SECRET_VERIFIER_SOURCE" \
  "$GHCR_PULL_VERIFIER_SOURCE" <<'PY'
from pathlib import Path
import sys
for value in sys.argv[1:]:
    source = Path(value).read_text(encoding="utf-8")
    compile(source, value, "exec")
PY
python3 "$DATA_PLATFORM_VERIFIER" "$REPOSITORY_ROOT" >/dev/null
visudo -cf "$SUDOERS_SOURCE" >/dev/null
install -d -o root -g root -m 0755 "$LIBRARY_TARGET"
install -d -o root -g root -m 0700 \
  /var/lib/blindou-data \
  /var/lib/blindou-data/releases \
  /var/lib/blindou-data/receipts \
  /var/lib/blindou-data/pull-proofs
install -o root -g root -m 0755 "$CONTROLLER_SOURCE" "$CONTROLLER_TARGET"
install -o root -g root -m 0755 "$RELEASE_VERIFIER_SOURCE" "${LIBRARY_TARGET}/blindou-data-release-verify.py"
install -o root -g root -m 0755 "$SECRET_VERIFIER_SOURCE" "${LIBRARY_TARGET}/blindou-data-secret-verify.py"
install -o root -g root -m 0755 "$GHCR_PULL_VERIFIER_SOURCE" "${LIBRARY_TARGET}/blindou-data-ghcr-pull-verify.py"
install -o root -g root -m 0440 "$SUDOERS_SOURCE" "$SUDOERS_TARGET"
visudo -cf "$SUDOERS_TARGET" >/dev/null
k3s kubectl apply -f "$APPLICATION_POLICY_SOURCE" >/dev/null
if ! k3s kubectl get namespace blindou-data >/dev/null 2>&1; then
  k3s kubectl apply -k "$DATA_PLATFORM_SOURCE" >/dev/null
else
  [[ "$(k3s kubectl get namespace blindou-data -o jsonpath='{.metadata.labels.platform\.servidor\.local/project}')" == 'blindou' \
      && "$(k3s kubectl get namespace blindou-data -o jsonpath='{.metadata.labels.platform\.servidor\.local/role}')" == 'data' ]] \
    || fail 'namespace blindou-data preexistente possui identidade divergente'
  k3s kubectl apply -f "$DATA_PLATFORM_SOURCE/20-workload-policy.yaml" >/dev/null
fi
data_gate="$(k3s kubectl get namespace blindou-data -o jsonpath='{.metadata.labels.platform\.servidor\.local/deployment-gate}')"
[[ "$data_gate" =~ ^(blocked|pull-only|candidate-foundation)$ ]] \
  || fail 'namespace de dados possui gate inesperado'
k3s kubectl get validatingadmissionpolicy blindou-data-workload-baseline >/dev/null \
  || fail 'política de admissão de dados não foi instalada'
sudo -u apiadmin sudo -n "$CONTROLLER_TARGET" status >/dev/null
sudo -u apiadmin sudo -n "$CONTROLLER_TARGET" verify-quarantine >/dev/null
printf '%s\n' 'blindou_datactl_bootstrap=installed'
