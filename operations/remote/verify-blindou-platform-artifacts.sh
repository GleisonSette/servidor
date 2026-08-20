#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REMOTE_DIR="${REPOSITORY_ROOT}/operations/remote"

fail() {
  printf '[verify-blindou-platform-artifacts] ERRO: %s\n' "$*" >&2
  exit 1
}

for script in \
  blindou-deployctl bootstrap-blindou-deployctl.sh blindou-platform-metrics; do
  bash -n "${REMOTE_DIR}/${script}"
done
python_command=''
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 \
      && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
    python_command="$candidate"
    break
  fi
done
[[ -n "$python_command" ]] || fail 'Python com PyYAML é obrigatório'
"$python_command" - "${REMOTE_DIR}/blindou-release-verify.py" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
compile(source, sys.argv[1], "exec")
PY
"$python_command" - "$REPOSITORY_ROOT" <<'PY'
from pathlib import Path
import sys
import yaml

root = Path(sys.argv[1])
paths = sorted((root / "platform/blindou").glob("*.yaml"))
paths.append(root / "platform/base/service-exposure-policy.yaml")
docs = []
for path in paths:
    docs.extend(doc for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")) if doc)

namespaces = {doc["metadata"]["name"]: doc for doc in docs if doc.get("kind") == "Namespace"}
if set(namespaces) != {"blindou-production", "blindou-edge"}:
    raise SystemExit("namespaces Blindou divergentes")
for namespace in namespaces.values():
    labels = namespace["metadata"]["labels"]
    if labels.get("platform.servidor.local/deployment-gate") != "blocked":
        raise SystemExit("namespace deve nascer bloqueado")
    if labels.get("pod-security.kubernetes.io/enforce") != "restricted":
        raise SystemExit("Pod Security deve ser restricted")

quotas = [doc for doc in docs if doc.get("kind") == "ResourceQuota"]
if len(quotas) != 2:
    raise SystemExit("eram esperadas duas quotas de quarentena")
for quota in quotas:
    hard = quota["spec"]["hard"]
    for key in ("pods", "services", "secrets", "persistentvolumeclaims"):
        if str(hard.get(key)) != "0":
            raise SystemExit(f"quarentena não bloqueia {key}")

if any(doc.get("kind") == "Secret" for doc in docs):
    raise SystemExit("fundação não pode conter Secret")
policies = {doc["metadata"]["name"] for doc in docs if doc.get("kind") == "ValidatingAdmissionPolicy"}
if not {"managed-production-workload-baseline", "shared-lab-private-services"}.issubset(policies):
    raise SystemExit("políticas de admissão obrigatórias ausentes")
PY

grep -Fq "readonly RELEASE_INBOX='/home/apiadmin/blindou-deploy-inbox'" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'inbox fechado ausente'
grep -Fq 'ssh-keygen -Y verify' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'verificação de assinatura ausente'
grep -Fq '"$source_state" == '\''clean'\''' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'release suja não está bloqueada'
grep -Fq 'clientcert=verify-ca' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'dupla autenticação PostgreSQL ausente'
grep -Fq 'include_if_exists "pg_hba_blindou.conf"' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'include HBA PostgreSQL válido ausente'
if grep -F "printf \"%s\\n\" \"include_if_exists 'pg_hba_blindou.conf'\"" \
    "${REMOTE_DIR}/blindou-deployctl" >/dev/null; then
  fail 'include HBA PostgreSQL usa aspas simples inválidas'
fi
grep -Fq 'cms -encrypt -binary -stream -aes-256-gcm' \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'backup criptografado forte ausente'
if grep -RInE '(BEGIN (RSA |OPENSSH )?PRIVATE KEY|(password|token|secret)[[:space:]]*[:=][[:space:]]*["'\'']?[[:alnum:]/+_.-]{12,})' \
    "${REPOSITORY_ROOT}/platform/blindou" "$REMOTE_DIR" >/dev/null; then
  fail 'possível segredo encontrado nos artefatos'
fi

if command -v visudo >/dev/null 2>&1; then
  visudo -cf "${REMOTE_DIR}/blindou-deployctl.sudoers" >/dev/null
fi

printf '%s\n' 'blindou_platform_artifacts=passed'
