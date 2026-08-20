#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly CONTROLLER="$REPOSITORY_ROOT/operations/remote/blindou-hostctl"
readonly BOOTSTRAP="$REPOSITORY_ROOT/operations/remote/bootstrap-blindou-hostctl.sh"
readonly SUDOERS_POLICY="$REPOSITORY_ROOT/operations/remote/blindou-hostctl.sudoers"

bash -n "$CONTROLLER"
bash -n "$BOOTSTRAP"

for marker in \
  blindou-deny-lan \
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
grep -Fq 'rollback-firewall' "$CONTROLLER"
grep -Fq 'ufw route insert 1' "$CONTROLLER"
grep -Fq "'/usr/local/sbin/blindou-hostctl'" "$BOOTSTRAP"
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
    root / "platform/base/namespaces.yaml",
    root / "platform/base/blindou-edge-space.yaml",
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
  '(sk_live_|sk_test_|eyJ[a-zA-Z0-9_-]{20,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)' \
  "$REPOSITORY_ROOT/operations" "$REPOSITORY_ROOT/platform" >/dev/null; then
  printf '%s\n' 'material sensível detectado' >&2
  exit 1
fi

printf '%s\n' 'blindou_temporary_artifacts=passed'
