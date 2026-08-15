#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
export DEBIAN_FRONTEND=noninteractive

if [[ "${EUID}" -ne 0 ]]; then
  printf '%s\n' 'maintenance-host.sh deve executar como root.' >&2
  exit 1
fi

test "$(hostname)" = apiwpp
ip -4 -o addr show dev enp2s0 | grep -Fq '192.168.100.59/'
systemctl is-active --quiet postgresql@18-main.service
systemctl is-active --quiet k3s.service

printf 'postgres_before=%s\n' "$(pg_config --version)"
printf 'pgbackrest_before=%s\n' "$(pgbackrest version)"

apt-get -o DPkg::Lock::Timeout=120 update
apt-get -o DPkg::Lock::Timeout=120 -y upgrade

systemctl start prometheus-postgres-exporter.service
if systemctl is-enabled --quiet apiwpp-private-gateway.service \
    && [[ -f /etc/apiwpp/private-gateway/nginx.conf ]]; then
  systemctl start apiwpp-private-gateway.service
fi

systemctl is-active --quiet postgresql@18-main.service
systemctl is-active --quiet k3s.service
systemctl is-active --quiet prometheus.service
systemctl is-active --quiet prometheus-node-exporter.service
systemctl is-active --quiet prometheus-postgres-exporter.service
systemctl is-active --quiet wg-quick@wg-apiwpp.service
if systemctl is-enabled --quiet apiwpp-private-gateway.service; then
  systemctl is-active --quiet apiwpp-private-gateway.service
fi
runuser -u postgres -- pg_isready -q
runuser -u postgres -- pgbackrest --stanza=apiwpp check >/dev/null
runuser -u postgres -- pgbackrest --stanza=apiwpp --repo=1 \
  info --output=json \
  | jq -e '.[0].status.code == 0 and (.[0].backup | length) > 0' >/dev/null
runuser -u postgres -- pgbackrest --stanza=apiwpp --repo=2 \
  info --output=json \
  | jq -e '.[0].status.code == 0 and (.[0].backup | length) > 0' >/dev/null

test "$(k3s kubectl get node apiwpp \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = True
bash /opt/apiwpp/deployer/infra/deploy/verify-deployment.sh

test -z "$(systemctl --failed --no-legend --plain)"
test "$(curl -fsS http://127.0.0.1:9090/api/v1/targets \
  | jq '[.data.activeTargets[] | select(.health != "up")] | length')" = 0
test "$(curl -fsS http://127.0.0.1:9090/api/v1/alerts \
  | jq '[.data.alerts[] | select(.state == "firing")] | length')" = 0

printf 'postgres_after=%s\n' "$(pg_config --version)"
printf 'pgbackrest_after=%s\n' "$(pgbackrest version)"
if [[ -e /var/run/reboot-required ]]; then
  printf '%s\n' 'reboot_required=yes'
else
  printf '%s\n' 'reboot_required=no'
fi
printf 'upgradable_remaining=%s\n' "$({ apt list --upgradable 2>/dev/null || true; } \
  | tail -n +2 | sed '/^$/d' | wc -l)"
printf '%s\n' 'maintenance_validation=passed'
