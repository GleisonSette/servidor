#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH

if [[ "${EUID}" -ne 0 ]]; then
  printf '%s\n' 'recover-dependent-services.sh deve executar como root.' >&2
  exit 1
fi
if [[ "$#" -ne 1 ]]; then
  printf 'uso: %s INBOX\n' "$0" >&2
  exit 2
fi

readonly INBOX="$(readlink -m "$1")"
readonly EXPECTED_PREFIX='/home/apiadmin/shared-lab-inbox-'
readonly EXPORTER_SOURCE="${INBOX}/prometheus-postgres-exporter.default"
readonly GATEWAY_SOURCE="${INBOX}/apiwpp-private-gateway.service"
readonly OBSERVABILITY_VERIFY_SOURCE="${INBOX}/verify-observability.sh"
readonly EXPORTER_TARGET='/etc/default/prometheus-postgres-exporter'
readonly EXPORTER_DROPIN='/etc/systemd/system/prometheus-postgres-exporter.service.d/apiwpp.conf'
readonly GATEWAY_TARGET='/etc/systemd/system/apiwpp-private-gateway.service'
readonly STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
readonly BACKUP_DIR="/var/backups/shared-lab/${STAMP}-dependent-services"

test "$(hostname)" = apiwpp
[[ "${INBOX}" == "${EXPECTED_PREFIX}"* ]]
test "$(stat -c '%U:%G' "${INBOX}")" = apiadmin:apiadmin
for source in \
  "${EXPORTER_SOURCE}" \
  "${GATEWAY_SOURCE}" \
  "${OBSERVABILITY_VERIFY_SOURCE}"; do
  [[ -f "${source}" && ! -L "${source}" ]]
  test "$(stat -c '%U:%G' "${source}")" = apiadmin:apiadmin
done
grep -Fq -- '--no-collector.stat_bgwriter' "${EXPORTER_SOURCE}"
grep -Fq 'PartOf=wg-quick@wg-apiwpp.service k3s.service' "${GATEWAY_SOURCE}"

install -d -o root -g root -m 0700 "${BACKUP_DIR}"
cp --archive "${EXPORTER_TARGET}" "${BACKUP_DIR}/prometheus-postgres-exporter.default"
cp --archive "${EXPORTER_DROPIN}" "${BACKUP_DIR}/prometheus-postgres-exporter-apiwpp.conf"
cp --archive "${GATEWAY_TARGET}" "${BACKUP_DIR}/apiwpp-private-gateway.service"

install -o root -g root -m 0644 "${EXPORTER_SOURCE}" "${EXPORTER_TARGET}"
cat > "${EXPORTER_DROPIN}" <<'EOF'
[Unit]
Requires=postgresql@18-main.service
After=postgresql@18-main.service
PartOf=postgresql@18-main.service
EOF
chmod 0644 "${EXPORTER_DROPIN}"
install -o root -g root -m 0644 "${GATEWAY_SOURCE}" "${GATEWAY_TARGET}"

systemd-analyze verify prometheus-postgres-exporter.service \
  apiwpp-private-gateway.service
systemctl daemon-reload
readonly START_EPOCH="$(date +%s)"
systemctl restart prometheus-postgres-exporter.service
systemctl restart apiwpp-private-gateway.service
systemctl is-active --quiet prometheus-postgres-exporter.service
systemctl is-active --quiet apiwpp-private-gateway.service

bash "${OBSERVABILITY_VERIFY_SOURCE}"
sleep 35
if journalctl -u prometheus-postgres-exporter.service \
    --since "@${START_EPOCH}" --no-pager \
    | grep -Fq 'collector failed" name=stat_bgwriter'; then
  printf '%s\n' 'Coletor stat_bgwriter incompatível continuou ativo.' >&2
  exit 3
fi

readonly GATEWAY_LISTENERS="$(ss -H -ltn 'sport = :8443' | awk '{print $4}')"
test "$(printf '%s\n' "${GATEWAY_LISTENERS}" | grep -Fxc '10.203.0.2:8443')" = 1
if printf '%s\n' "${GATEWAY_LISTENERS}" \
    | grep -Eq '(^|\[)(0\.0\.0\.0|::)(\]|):8443$'; then
  printf '%s\n' 'Gateway privado possui listener público.' >&2
  exit 4
fi

bash /opt/apiwpp/deployer/infra/deploy/verify-deployment.sh
test -z "$(systemctl --failed --no-legend --plain)"
printf 'dependent_services=passed backup_dir=%s\n' "${BACKUP_DIR}"
