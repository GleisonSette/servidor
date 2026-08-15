#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH

if [[ "${EUID}" -ne 0 ]]; then
  printf '%s\n' 'verify-platform.sh deve executar como root.' >&2
  exit 1
fi

test "$(hostname)" = apiwpp
ip -4 -o addr show dev enp2s0 | grep -Fq '192.168.100.59/'
for service in \
  k3s.service \
  postgresql@18-main.service \
  prometheus.service \
  prometheus-node-exporter.service \
  prometheus-postgres-exporter.service \
  wg-quick@wg-apiwpp.service \
  apiwpp-private-gateway.service; do
  systemctl is-active --quiet "${service}"
done
test -z "$(systemctl --failed --no-legend --plain)"
ufw status | grep -Fq 'Status: active'

test "$(k3s kubectl get node apiwpp \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = True
k3s secrets-encrypt status | grep -Fq 'Encryption Status: Enabled'

readonly AUDIT_POLICY='/var/lib/rancher/k3s/server/audit.yaml'
readonly AUDIT_CONFIG='/etc/rancher/k3s/config.yaml.d/20-shared-lab.yaml'
readonly AUDIT_LOG='/var/lib/rancher/k3s/server/logs/audit.log'
test "$(stat -c '%U:%G:%a' "${AUDIT_POLICY}")" = root:root:600
test "$(stat -c '%U:%G:%a' "${AUDIT_CONFIG}")" = root:root:600
test -s "${AUDIT_LOG}"
grep -Fq 'audit-log-maxage=14' "${AUDIT_CONFIG}"
grep -Fq 'audit-log-maxbackup=5' "${AUDIT_CONFIG}"
grep -Fq 'audit-log-maxsize=50' "${AUDIT_CONFIG}"
if tail -n 500 "${AUDIT_LOG}" \
    | jq -e 'select(.objectRef.resource == "secrets")
        | select(has("requestObject") or has("responseObject"))' >/dev/null; then
  printf '%s\n' 'Audit log registrou corpo de Secret.' >&2
  exit 2
fi

for namespace in cia-pixel-lab saferwpp-lab; do
  test "$(k3s kubectl get namespace "${namespace}" \
    -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')" = restricted
  test "$(k3s kubectl get namespace "${namespace}" \
    -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce-version}')" = v1.36
  test "$(k3s kubectl -n "${namespace}" get serviceaccount default \
    -o jsonpath='{.automountServiceAccountToken}')" = false
  k3s kubectl -n "${namespace}" get resourcequota project-budget >/dev/null
  k3s kubectl -n "${namespace}" get limitrange workload-defaults >/dev/null
  test "$(k3s kubectl -n "${namespace}" get networkpolicy -o name | wc -l)" = 2
  test -z "$(k3s kubectl -n "${namespace}" get pods -o name)"
  test -z "$(k3s kubectl -n "${namespace}" get services -o name)"
done

if k3s kubectl -n saferwpp-lab create service nodeport admission-test \
    --tcp=8080:8080 --dry-run=server -o yaml >/dev/null 2>&1; then
  printf '%s\n' 'Política de admissão aceitou NodePort.' >&2
  exit 3
fi

test "$(k3s kubectl -n apiwpp get pods -o json \
  | jq '[.items[] | select(any(.status.containerStatuses[]?;
      .state.terminated.reason == "ContainerStatusUnknown"))] | length')" = 0
bash /opt/apiwpp/deployer/infra/deploy/verify-deployment.sh

runuser -u postgres -- pg_isready -q
runuser -u postgres -- pgbackrest --stanza=apiwpp check >/dev/null
test "$(curl -fsS http://127.0.0.1:9090/api/v1/targets \
  | jq '[.data.activeTargets[] | select(.health != "up")] | length')" = 0
test "$(curl -fsS http://127.0.0.1:9090/api/v1/alerts \
  | jq '[.data.alerts[] | select(.state == "firing")] | length')" = 0

readonly METRICS_EXPOSED="$(ss -H -lnt \
  | awk '$4 ~ /:(9090|9100|9187)$/ && $4 !~ /^127\.0\.0\.1:/ {print}')"
test -z "${METRICS_EXPOSED}"
test "$(ss -H -ltn 'sport = :8443' | awk '{print $4}' \
  | grep -Fxc '10.203.0.2:8443')" = 1

readonly K3S_BACKUP_DIR="$(find /var/backups/shared-lab \
  -mindepth 2 -maxdepth 2 -type f -name SHA256SUMS -printf '%h\n' \
  | sort | tail -n 1)"
[[ "${K3S_BACKUP_DIR}" == /var/backups/shared-lab/* ]]
(cd "${K3S_BACKUP_DIR}" && sha256sum --check SHA256SUMS >/dev/null)
test ! -e /var/run/reboot-required
test "$(apt list --upgradable 2>/dev/null | tail -n +2 \
  | sed '/^$/d' | wc -l)" = 0

printf 'k3s=%s\n' "$(k3s --version | awk 'NR == 1 {print $3}')"
printf 'postgres=%s\n' "$(pg_config --version)"
printf 'pgbackrest=%s\n' "$(pgbackrest version)"
printf 'k3s_backup=%s\n' "${K3S_BACKUP_DIR}"
printf '%s\n' 'platform_verification=passed'
