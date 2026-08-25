#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly CONTROLLER="$REPOSITORY_ROOT/operations/remote/blindou-hostctl"
readonly BOOTSTRAP="$REPOSITORY_ROOT/operations/remote/bootstrap-blindou-hostctl.sh"
readonly SUDOERS_POLICY="$REPOSITORY_ROOT/operations/remote/blindou-hostctl.sudoers"
readonly SERVICE="$REPOSITORY_ROOT/operations/remote/blindou-temporary-containment.service"

bash -n "$CONTROLLER"
bash -n "$BOOTSTRAP"
[[ -f "$SERVICE" && ! -L "$SERVICE" ]]

for marker in \
  blindou-deny-rfc1918-10 \
  blindou-deny-rfc1918-172 \
  blindou-deny-rfc1918-192 \
  blindou-deny-cgnat \
  blindou-deny-linklocal \
  blindou-route-deny-lan \
  blindou-route-deny-rfc1918-10 \
  blindou-route-deny-rfc1918-172 \
  blindou-route-deny-rfc1918-192 \
  blindou-route-deny-cgnat \
  blindou-route-deny-linklocal \
  blindou-route-allow-dns-udp \
  blindou-route-allow-dns-tcp \
  blindou-allow-dhcp \
  blindou-allow-dns-udp \
  blindou-allow-dns-tcp \
  blindou-deny-lan-inbound \
  blindou-admin-ssh \
  blindou-admin-k3s; do
  grep -Fq "$marker" "$CONTROLLER"
done

grep -Fq 'disable_ipv6 = 1' "$CONTROLLER"
grep -Fq 'write_ipv6_containment' "$CONTROLLER"
grep -Fq 'rollback-firewall' "$CONTROLLER"
grep -Fq 'ufw route insert 1' "$CONTROLLER"
grep -Fq 'o UFW não efetivou a regra identificada' "$CONTROLLER"
grep -Fq 'rollback automático concluído' "$CONTROLLER"
grep -Fq 'timeout 8 resolvectl query' "$CONTROLLER"
grep -Fq "'/usr/local/sbin/blindou-hostctl'" "$BOOTSTRAP"
grep -Fq 'systemctl enable blindou-temporary-containment.service' "$BOOTSTRAP"
grep -Fq 'After=systemd-sysctl.service systemd-networkd.service network-online.target' "$SERVICE"
grep -Fq 'Before=k3s.service apiwpp-private-gateway.service' "$SERVICE"
grep -Fq 'ExecStart=/usr/sbin/sysctl --quiet --load=/etc/sysctl.d/90-blindou-temporary-network.conf' "$SERVICE"
grep -Fq 'apply-firewall blindou-temporary-host-containment' "$SUDOERS_POLICY"
grep -Fq 'visudo -cf' "$BOOTSTRAP"
if grep -Eq '^apiadmin .*NOPASSWD:.*rollback-firewall' "$SUDOERS_POLICY"; then
  printf '%s\n' 'rollback não pode ser liberado sem senha' >&2
  exit 1
fi

python_command=''
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 \
      && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
    python_command="$candidate"
    break
  fi
done
[[ -n "$python_command" ]] \
  || { printf '%s\n' 'Python com PyYAML é obrigatório' >&2; exit 1; }

"$python_command" - "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
import yaml

root = Path(sys.argv[1])
paths = [
    root / "platform/blindou/00-namespaces.yaml",
    root / "platform/security/blindou-edge-policy.yaml",
]
documents = []
for path in paths:
    documents.extend(
        doc for doc in yaml.safe_load_all(path.read_text(encoding="utf-8"))
        if doc is not None
    )
for document in documents:
    for key in ("apiVersion", "kind", "metadata"):
        if key not in document:
            raise SystemExit(f"documento sem {key}")

namespaces = {
    doc["metadata"]["name"]
    for doc in documents
    if doc["kind"] == "Namespace"
}
if "blindou-edge" not in namespaces or "blindou-production" not in namespaces:
    raise SystemExit("namespaces Blindou ausentes")

policy = next(doc for doc in documents if doc["kind"] == "NetworkContainmentPolicy")
threat = policy["spec"]["threatModel"]
if threat.get("containPhysicalHostRootCompromise") is not False:
    raise SystemExit("a política não pode prometer contenção de root")
if policy["spec"]["temporaryTopology"].get("definitiveDestination") != "vultr":
    raise SystemExit("a expiração Vultr deve ser explícita")
PY

if grep -R -nE \
  --exclude='verify-blindou-temporary-artifacts.sh' \
  '(sk_(test_)?[A-Za-z0-9]{16,}|eyJ[a-zA-Z0-9_-]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)' \
  "$REPOSITORY_ROOT/operations" "$REPOSITORY_ROOT/platform" >/dev/null; then
  printf '%s\n' 'material sensível detectado' >&2
  exit 1
fi

printf '%s\n' 'blindou_temporary_artifacts=passed'
