#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
umask 077

readonly EXPECTED_HOSTNAME='apiwpp'
readonly SOURCE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SOURCE_DIRECTORY}/../.." && pwd)"
readonly CONTROLLER_SOURCE="${SOURCE_DIRECTORY}/blindou-deployctl"
readonly VERIFIER_SOURCE="${SOURCE_DIRECTORY}/blindou-release-verify.py"
readonly METRICS_SOURCE="${SOURCE_DIRECTORY}/blindou-platform-metrics"
readonly METRICS_SERVICE_SOURCE="${SOURCE_DIRECTORY}/blindou-platform-metrics.service"
readonly METRICS_TIMER_SOURCE="${SOURCE_DIRECTORY}/blindou-platform-metrics.timer"
readonly SUDOERS_SOURCE="${SOURCE_DIRECTORY}/blindou-deployctl.sudoers"
readonly SIGNERS_SOURCE="${SOURCE_DIRECTORY}/blindou-release-allowed-signers"
readonly RECIPIENT_SOURCE="${SOURCE_DIRECTORY}/blindou-backup-recipient.crt"
readonly PLATFORM_SOURCE="${REPOSITORY_ROOT}/platform/blindou"
readonly SERVICE_POLICY_SOURCE="${REPOSITORY_ROOT}/platform/base/service-exposure-policy.yaml"
readonly CONTROLLER_TARGET='/usr/local/sbin/blindou-deployctl'
readonly METRICS_TARGET='/usr/local/sbin/blindou-platform-metrics'
readonly LIBRARY_TARGET='/usr/local/lib/blindou-platform'
readonly FOUNDATION_TARGET="${LIBRARY_TARGET}/foundation"
readonly SUDOERS_TARGET='/etc/sudoers.d/blindou-deployctl'
readonly DATA_ROOT='/etc/blindou'

fail() {
  printf '[bootstrap-blindou-deployctl] ERRO: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'
[[ "$(hostname)" == "$EXPECTED_HOSTNAME" ]] || fail 'hostname inesperado'
for source in \
  "$CONTROLLER_SOURCE" "$VERIFIER_SOURCE" "$METRICS_SOURCE" \
  "$METRICS_SERVICE_SOURCE" "$METRICS_TIMER_SOURCE" "$SUDOERS_SOURCE" \
  "$SIGNERS_SOURCE" "$RECIPIENT_SOURCE" "$SERVICE_POLICY_SOURCE" \
  "${PLATFORM_SOURCE}/00-namespaces.yaml" \
  "${PLATFORM_SOURCE}/10-quarantine.yaml" \
  "${PLATFORM_SOURCE}/15-edge-connector-gate.yaml" \
  "${PLATFORM_SOURCE}/16-edge-connector-runtime.yaml" \
  "${PLATFORM_SOURCE}/20-production-workload-policy.yaml"; do
  [[ -f "$source" && ! -L "$source" ]] || fail "fonte ausente ou simbólica: ${source}"
done

bash -n "$CONTROLLER_SOURCE"
bash -n "$METRICS_SOURCE"
python3 -m py_compile "$VERIFIER_SOURCE"
python3 - "$PLATFORM_SOURCE" "$SERVICE_POLICY_SOURCE" <<'PY'
from pathlib import Path
import sys
import yaml

paths = sorted(Path(sys.argv[1]).glob("*.yaml")) + [Path(sys.argv[2])]
documents = []
for path in paths:
    documents.extend(doc for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")) if doc)
if not documents:
    raise SystemExit("manifests da fundação estão vazios")
if any(doc.get("kind") == "Secret" for doc in documents):
    raise SystemExit("a fundação não pode conter Secret")
PY
visudo -cf "$SUDOERS_SOURCE" >/dev/null
[[ "$(wc -l <"$SIGNERS_SOURCE")" == '1' ]] || fail 'allowed_signers deve conter uma linha'
grep -Eq '^blindou-local[[:space:]]+ssh-ed25519[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$' \
  "$SIGNERS_SOURCE" || fail 'allowed_signers inválido'
openssl x509 -in "$RECIPIENT_SOURCE" -noout -purpose \
  | grep -Fq 'S/MIME encryption : Yes' \
  || fail 'certificado de recuperação não aceita criptografia S/MIME'
openssl x509 -checkend 31536000 -noout -in "$RECIPIENT_SOURCE" \
  || fail 'certificado de recuperação expira em menos de um ano'

install -d -o root -g root -m 0755 "$LIBRARY_TARGET"
install -d -o root -g root -m 0755 "$FOUNDATION_TARGET"
install -d -o root -g root -m 0700 "${DATA_ROOT}/deploy" "${DATA_ROOT}/backup"
install -o root -g root -m 0755 "$CONTROLLER_SOURCE" "$CONTROLLER_TARGET"
install -o root -g root -m 0755 "$VERIFIER_SOURCE" "${LIBRARY_TARGET}/blindou-release-verify.py"
install -o root -g root -m 0755 "$METRICS_SOURCE" "$METRICS_TARGET"
install -o root -g root -m 0644 \
  "${PLATFORM_SOURCE}/00-namespaces.yaml" "${FOUNDATION_TARGET}/00-namespaces.yaml"
install -o root -g root -m 0644 \
  "${PLATFORM_SOURCE}/10-quarantine.yaml" "${FOUNDATION_TARGET}/10-quarantine.yaml"
install -o root -g root -m 0644 \
  "${PLATFORM_SOURCE}/15-edge-connector-gate.yaml" \
  "${FOUNDATION_TARGET}/15-edge-connector-gate.yaml"
install -o root -g root -m 0644 \
  "${PLATFORM_SOURCE}/16-edge-connector-runtime.yaml" \
  "${FOUNDATION_TARGET}/16-edge-connector-runtime.yaml"
install -o root -g root -m 0644 \
  "${PLATFORM_SOURCE}/20-production-workload-policy.yaml" \
  "${FOUNDATION_TARGET}/20-production-workload-policy.yaml"
install -o root -g root -m 0644 "$SERVICE_POLICY_SOURCE" \
  "${FOUNDATION_TARGET}/shared-service-exposure-policy.yaml"
install -o root -g root -m 0644 "$SIGNERS_SOURCE" "${DATA_ROOT}/deploy/allowed_signers"
install -o root -g root -m 0644 "$RECIPIENT_SOURCE" \
  "${DATA_ROOT}/backup/recovery-recipient.crt"
install -o root -g root -m 0440 "$SUDOERS_SOURCE" "$SUDOERS_TARGET"
install -o root -g root -m 0644 "$METRICS_SERVICE_SOURCE" \
  /etc/systemd/system/blindou-platform-metrics.service
install -o root -g root -m 0644 "$METRICS_TIMER_SOURCE" \
  /etc/systemd/system/blindou-platform-metrics.timer
visudo -cf "$SUDOERS_TARGET" >/dev/null
systemctl daemon-reload
systemctl enable --now blindou-platform-metrics.timer >/dev/null
systemctl start blindou-platform-metrics.service
sudo -u apiadmin sudo -n "$CONTROLLER_TARGET" status >/dev/null
printf '%s\n' 'blindou_deployctl_bootstrap=installed'
