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
base_paths = [
    root / "platform/blindou/00-namespaces.yaml",
    root / "platform/blindou/10-quarantine.yaml",
    root / "platform/blindou/20-production-workload-policy.yaml",
    root / "platform/base/service-exposure-policy.yaml",
]
paths = sorted((root / "platform/blindou").glob("*.yaml"))
paths.append(root / "platform/base/service-exposure-policy.yaml")
docs = []
for path in paths:
    docs.extend(doc for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")) if doc)
base_docs = []
for path in base_paths:
    base_docs.extend(doc for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")) if doc)

namespaces = {doc["metadata"]["name"]: doc for doc in base_docs if doc.get("kind") == "Namespace"}
if set(namespaces) != {"blindou-production", "blindou-edge"}:
    raise SystemExit("namespaces Blindou divergentes")
for namespace in namespaces.values():
    labels = namespace["metadata"]["labels"]
    if labels.get("platform.servidor.local/deployment-gate") != "blocked":
        raise SystemExit("namespace deve nascer bloqueado")
    if labels.get("pod-security.kubernetes.io/enforce") != "restricted":
        raise SystemExit("Pod Security deve ser restricted")

quotas = [doc for doc in base_docs if doc.get("kind") == "ResourceQuota"]
if len(quotas) != 2:
    raise SystemExit("eram esperadas duas quotas de quarentena")
for quota in quotas:
    hard = quota["spec"]["hard"]
    for key in ("pods", "services", "secrets", "persistentvolumeclaims"):
        if str(hard.get(key)) != "0":
            raise SystemExit(f"quarentena não bloqueia {key}")

if any(doc.get("kind") == "Secret" for doc in docs):
    raise SystemExit("fundação não pode conter Secret")
edge_docs = [
    doc
    for path in (
        root / "platform/blindou/15-edge-connector-gate.yaml",
        root / "platform/blindou/16-edge-connector-runtime.yaml",
    )
    for doc in yaml.safe_load_all(path.read_text(encoding="utf-8"))
    if doc
]
edge_namespace = next(doc for doc in edge_docs if doc.get("kind") == "Namespace")
if edge_namespace["metadata"]["labels"].get(
    "platform.servidor.local/deployment-gate"
) != "connector-only":
    raise SystemExit("gate dedicado do conector Cloudflare ausente")
edge_quota = next(doc for doc in edge_docs if doc.get("kind") == "ResourceQuota")
expected_quota = {
    "pods": "1",
    "services": "0",
    "secrets": "1",
    "persistentvolumeclaims": "0",
    "configmaps": "1",
}
actual_quota = {key: str(value) for key, value in edge_quota["spec"]["hard"].items()}
if actual_quota != expected_quota:
    raise SystemExit("quota dedicada do conector Cloudflare diverge")
deployment = next(doc for doc in edge_docs if doc.get("kind") == "Deployment")
pod_spec = deployment["spec"]["template"]["spec"]
container = pod_spec["containers"][0]
if not container["image"].startswith("docker.io/cloudflare/cloudflared@sha256:"):
    raise SystemExit("imagem cloudflared nao esta fixada por digest")
if pod_spec.get("automountServiceAccountToken") is not False:
    raise SystemExit("cloudflared nao desabilita token da ServiceAccount")
if any(doc.get("kind") in {"Secret", "Service", "PersistentVolumeClaim"} for doc in edge_docs):
    raise SystemExit("manifesto do conector contem objeto proibido")

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
grep -Fq 'pgrep -x cloudflared' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'detecção exata do processo cloudflared ausente'
grep -Fq "readonly EDGE_CONNECTOR_CONFIRMATION='blindou-edge-connector'" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'confirmação fechada do conector ausente'
grep -Fq "[[ ! -t 0 ]]" "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'token do Tunnel não exige stdin não interativo'
grep -Fq -- '--from-file=token=/dev/stdin' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'token do Tunnel não entra diretamente no Secret'
grep -Fq 'rollback_edge_connector_internal' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'rollback do conector Cloudflare ausente'
grep -Fq "readonly CLOUDFLARE_SAAS_TOKEN_FILE=\"\${CLOUDFLARE_SAAS_SECRET_DIR}/api-token\"" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'cofre root-only do token SaaS ausente'
grep -Fq "readonly CLOUDFLARE_SAAS_ZONE_ID='e0bb5f20a8e4f928d008cb8dc7876202'" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'escopo da zona Blindou ausente'
grep -Fq 'Cloudflare for SaaS token must arrive through non-interactive stdin' \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'token SaaS não exige stdin fechado'
grep -Fq "'https://api.cloudflare.com/client/v4/user/tokens/verify'" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'verificação ativa do token SaaS ausente'
grep -Fq '/custom_hostnames?per_page=1' \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'verificação de acesso aos hostnames ausente'
grep -Fq '| curl --config -' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'token SaaS seria exposto nos argumentos do curl'
grep -Fq 'CLOUDFLARE_SAAS_API_TOKEN' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'gate de release não exige o token SaaS'
[[ "$(grep -Fc 'if ( verify_edge_connector >/dev/null 2>&1 ); then' \
  "${REMOTE_DIR}/blindou-deployctl")" == '2' ]] \
  || fail 'sondagem do conector precisa isolar falha esperada em subshell'
[[ "$(grep -Fc 'if ( verify_foundation >/dev/null 2>&1 ); then' \
  "${REMOTE_DIR}/blindou-deployctl")" == '2' ]] \
  || fail 'sondagem da fundação precisa isolar falha esperada em subshell'
grep -Fq 'if ( verify_data_foundation >/dev/null 2>&1 ); then' \
  "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'sondagem dos dados precisa isolar falha esperada em subshell'
grep -Fq 'systemctl start --wait blindou-platform-metrics.service' \
  "${REMOTE_DIR}/bootstrap-blindou-deployctl.sh" \
  || fail 'bootstrap não aguarda a coleta inicial liberar o controlador'
if grep -F "printf \"%s\\n\" \"include_if_exists 'pg_hba_blindou.conf'\"" \
    "${REMOTE_DIR}/blindou-deployctl" >/dev/null; then
  fail 'include HBA PostgreSQL usa aspas simples inválidas'
fi
grep -Fq 'cms -encrypt -binary -stream -aes-256-gcm' \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'backup criptografado forte ausente'
if grep -RInE --exclude-dir=__pycache__ \
    '(BEGIN (RSA |OPENSSH )?PRIVATE KEY|(password|token|secret)[[:space:]]*[:=][[:space:]]*["'\'']?[[:alnum:]/+_.-]{12,})' \
    "${REPOSITORY_ROOT}/platform/blindou" "$REMOTE_DIR" >/dev/null; then
  fail 'possível segredo encontrado nos artefatos'
fi

if command -v visudo >/dev/null 2>&1; then
  visudo -cf "${REMOTE_DIR}/blindou-deployctl.sudoers" >/dev/null
fi

printf '%s\n' 'blindou_platform_artifacts=passed'
