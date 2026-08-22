#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REMOTE_DIR="${REPOSITORY_ROOT}/operations/remote"
readonly PULL_PROOF_SCRIPT="${REPOSITORY_ROOT}/operations/Invoke-BlindouGhcrCandidatePullProof.ps1"
readonly SUDO_BOOTSTRAP_MODULE="${REPOSITORY_ROOT}/operations/Blindou.SudoBootstrap.psm1"
readonly FIRST_RELEASE_SCRIPT="${REPOSITORY_ROOT}/operations/Invoke-BlindouFirstRelease.ps1"
readonly EMERGENCY_CONTROLLER="${REMOTE_DIR}/blindou-release-emergencyctl"

fail() {
  printf '[verify-blindou-platform-artifacts] ERRO: %s\n' "$*" >&2
  exit 1
}

[[ -f "$PULL_PROOF_SCRIPT" && ! -L "$PULL_PROOF_SCRIPT" ]] \
  || fail 'orquestrador da prova GHCR ausente ou simbólico'
[[ -f "$SUDO_BOOTSTRAP_MODULE" && ! -L "$SUDO_BOOTSTRAP_MODULE" ]] \
  || fail 'módulo fechado de bootstrap sudo ausente ou simbólico'
[[ -f "$FIRST_RELEASE_SCRIPT" && ! -L "$FIRST_RELEASE_SCRIPT" ]] \
  || fail 'orquestrador fechado da primeira release ausente ou simbólico'
[[ -f "$EMERGENCY_CONTROLLER" && ! -L "$EMERGENCY_CONTROLLER" ]] \
  || fail 'controlador fechado de contenção emergencial ausente ou simbólico'
bash -n "$EMERGENCY_CONTROLLER"
grep -Fq 'cmdline" == "bash ${CONTROLLER} apply ${release_id} "' \
  "$EMERGENCY_CONTROLLER" \
  || fail 'contenção emergencial não fixa o processo apply exato'
grep -Fq 'pgrep -f "^bash ${CONTROLLER} apply ${release_id}$"' \
  "$EMERGENCY_CONTROLLER" \
  || fail 'contenção emergencial não seleciona um único apply por cmdline'
grep -Fq 'if flock --nonblock 8; then' "$EMERGENCY_CONTROLLER" \
  || fail 'contenção emergencial não comprova que o apply segura o lock'
grep -Fq "'platform.servidor.local/deployment-gate=secrets-only'" \
  "$EMERGENCY_CONTROLLER" \
  || fail 'contenção emergencial não restaura secrets-only'
grep -Fq 'workload ou Service parcial permaneceu na aplicação' \
  "$EMERGENCY_CONTROLLER" \
  || fail 'contenção emergencial não verifica ausência de workload parcial'
grep -Fq 'rollout status deployment/blindou-cloudflared' \
  "$EMERGENCY_CONTROLLER" \
  || fail 'contenção emergencial não aguarda o conector isolado voltar'
grep -Fq 'blindou-release-emergencyctl contain-stuck-first-release * blindou-stuck-first-release' \
  "${REMOTE_DIR}/blindou-deployctl.sudoers" \
  || fail 'sudoers não limita a contenção emergencial ao contrato fechado'
grep -Fq 'EMERGENCY_CONTROLLER_SOURCE' "${REMOTE_DIR}/bootstrap-blindou-deployctl.sh" \
  || fail 'bootstrap não instala o controlador emergencial'
grep -Fq "'operations/remote/blindou-release-emergencyctl'" "$PULL_PROOF_SCRIPT" \
  || fail 'bootstrap administrativo não transporta o controlador emergencial'
grep -Fq "[ValidateSet('DeployController', 'HostAndDeployControllers')]" \
  "$SUDO_BOOTSTRAP_MODULE" || fail 'bootstrap sudo aceita conjunto não fechado'
grep -Fq "if (\$Server -cne 'apiadmin@192.168.100.59')" \
  "$SUDO_BOOTSTRAP_MODULE" || fail 'bootstrap sudo não fixa o servidor aprovado'
grep -Fq "sudo -S -p '' -- ./operations/remote/bootstrap-blindou-deployctl.sh" \
  "$SUDO_BOOTSTRAP_MODULE" || fail 'bootstrap sudo do deployctl não usa stdin'
grep -Fq "sudo -S -p '' -- ./operations/remote/bootstrap-blindou-hostctl.sh" \
  "$SUDO_BOOTSTRAP_MODULE" || fail 'bootstrap sudo do hostctl não usa stdin'
grep -Fq "Join-Path \$repositoryRoot '.env'" \
  "$SUDO_BOOTSTRAP_MODULE" || fail 'bootstrap sudo não fixa o arquivo temporário local'
if grep -Eq 'Write-(Host|Output|Verbose|Debug).*(password|KEY_SERVIDOR)' \
    "$SUDO_BOOTSTRAP_MODULE"; then
  fail 'bootstrap sudo pode revelar a senha'
fi
grep -Fq '[string]$BundleDirectory' "$PULL_PROOF_SCRIPT" \
  || fail 'orquestrador não exige o diretório do bundle assinado'
grep -Fq 'sudo -n /usr/local/sbin/blindou-deployctl validate-release $ReleaseId' \
  "$PULL_PROOF_SCRIPT" || fail 'orquestrador não valida a release antes do pull'
grep -Fq "'release.manifest.sig'" "$PULL_PROOF_SCRIPT" \
  || fail 'orquestrador não fecha os três artefatos da release'
grep -Fq 'Invoke-BlindouSudoBootstrap' "$PULL_PROOF_SCRIPT" \
  || fail 'orquestrador não usa o bootstrap sudo fechado'
if grep -Eq 'Admin token da UAZAPI|API key do Resend|PAGARME_' "$FIRST_RELEASE_SCRIPT"; then
  fail 'primeira revisão da UI solicita provedor externo antes da aprovação'
fi
grep -Fq 'provision-ui-review-runtime blindou-ui-review-runtime' "$FIRST_RELEASE_SCRIPT" \
  || fail 'primeira revisão não usa o modo fechado sem provedores'
grep -Fq 'function Invoke-RemoteDeployControl' "$FIRST_RELEASE_SCRIPT" \
  || fail 'primeira release não classifica contenção temporária do controlador'
grep -Fq 'if ($exitCode -ne 2)' "$FIRST_RELEASE_SCRIPT" \
  || fail 'retry da primeira release não é restrito ao lock ocupado'
grep -Fq 'for ($attempt = 1; $attempt -le 12; $attempt++)' \
  "$FIRST_RELEASE_SCRIPT" \
  || fail 'retry da primeira release não possui limite fechado'
if grep -Fq 'activate-release-gates $ReleaseId blindou-release-gates &&' \
  "$FIRST_RELEASE_SCRIPT"; then
  fail 'ativação dos gates e apply não podem compartilhar retry ambíguo'
fi
grep -Fq "Read-Host 'Senha do superadmin' -AsSecureString" "$FIRST_RELEASE_SCRIPT" \
  || fail 'senha do superadmin não usa entrada protegida'
grep -Fq 'Invoke-ClosedSshInput' "$FIRST_RELEASE_SCRIPT" \
  || fail 'segredos não usam o canal SSH por stdin'
if grep -Eq 'ssh\.exe.*(UAZAPI|RESEND|plainPassword|plainResend|plainUazapi)' \
    "$FIRST_RELEASE_SCRIPT"; then
  fail 'possível segredo encontrado em argumento SSH'
fi
if grep -Fq "Join-Path \$repositoryRoot '.env'" "$FIRST_RELEASE_SCRIPT"; then
  fail 'orquestrador de runtime não pode ler a senha administrativa temporária'
fi
for orchestrator in \
  Invoke-BlindouCloudflareConnector.ps1 \
  Invoke-BlindouCloudflareSaasToken.ps1 \
  Invoke-BlindouGhcrPullCredential.ps1 \
  Invoke-BlindouGhcrCandidatePullProof.ps1; do
  grep -Fq "Import-Module (Join-Path \$PSScriptRoot 'Blindou.SudoBootstrap.psm1') -Force" \
    "${REPOSITORY_ROOT}/operations/${orchestrator}" \
    || fail "orquestrador não importa helper sudo: ${orchestrator}"
  grep -Fq 'Invoke-BlindouSudoBootstrap' \
    "${REPOSITORY_ROOT}/operations/${orchestrator}" \
    || fail "orquestrador não usa helper sudo: ${orchestrator}"
done
for orchestrator in \
  Invoke-BlindouCloudflareConnector.ps1 \
  Invoke-BlindouCloudflareSaasToken.ps1; do
  grep -Fq 'operations/remote/blindou-ghcr-pull-verify.py' \
    "${REPOSITORY_ROOT}/operations/${orchestrator}" \
    || fail "orquestrador não transporta verificador GHCR: ${orchestrator}"
done

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
"$python_command" - "${REMOTE_DIR}/blindou-ghcr-pull-verify.py" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
compile(source, sys.argv[1], "exec")
PY
"$python_command" "${REMOTE_DIR}/test-blindou-ghcr-pull-verify.py"
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
grep -Fq "readonly GHCR_PULL_TOKEN_FILE=\"\${GHCR_SECRET_DIR}/pull-token\"" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'cofre root-only do GHCR ausente'
grep -Fq "readonly GHCR_PULL_CONFIRMATION='blindou-ghcr-pull-credential'" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'confirmação fechada do GHCR ausente'
grep -Fq 'GHCR credential must arrive through non-interactive stdin' \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'credencial GHCR não exige stdin fechado'
grep -Fq "[[ \"\$scopes\" == 'read:packages' ]]" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'escopo GHCR não está fechado em read:packages'
grep -Fq -- '--type=kubernetes.io/dockerconfigjson' \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'pull secret GHCR não usa o tipo Kubernetes esperado'
grep -Fq -- '--from-file=.dockerconfigjson=/dev/stdin' \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'credencial GHCR não entra diretamente no Secret'
grep -Fq 'ensure_ghcr_pull_secret' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'release não materializa o pull secret pelo controlador'
grep -Fq 'attach_edge_pull_credential' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'cloudflared privado não recebe a credencial GHCR somente leitura'
grep -Fq "readonly RUNTIME_SECRETS_CONFIRMATION='blindou-runtime-secrets'" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'confirmação fechada dos Secrets ausente'
grep -Fq 'provision-runtime-secrets)' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'operação fechada de Secrets ausente'
grep -Fq 'provision-ui-review-runtime)' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'operação fail-closed para revisão da UI ausente'
ui_review_runtime_function="$(sed -n '/^provision_ui_review_runtime()/,/^}/p' \
  "${REMOTE_DIR}/blindou-deployctl")"
grep -Fq 'install -d -o root -g root -m 0700 "$RUNTIME_SECRET_DIR"' \
  <<<"$ui_review_runtime_function" \
  || fail 'revisão da UI não cria o cofre antes de gravar production.env'
ui_review_dir_line="$(grep -nF 'install -d -o root -g root -m 0700 "$RUNTIME_SECRET_DIR"' \
  <<<"$ui_review_runtime_function" | cut -d: -f1)"
ui_review_config_line="$(grep -nF 'write_ui_review_runtime_config' \
  <<<"$ui_review_runtime_function" | cut -d: -f1)"
[[ "$ui_review_dir_line" =~ ^[0-9]+$ && "$ui_review_config_line" =~ ^[0-9]+$ \
  && "$ui_review_dir_line" -lt "$ui_review_config_line" ]] \
  || fail 'cofre da revisão da UI não precede a gravação de production.env'
grep -Fq "[[ ! -t 0 ]] || fail 'segredos de runtime devem chegar por stdin" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'Secrets de runtime não exigem stdin fechado'
grep -Fq 'AUTH_REQUIRE_2FA=false' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'gate temporário de 2FA ausente'
if grep -A40 '^require_release_gates()' "${REMOTE_DIR}/blindou-deployctl" \
    | grep -Fq 'AUTH_SECURITY_WHATSAPP_SENDER_TOKEN'; then
  fail 'gate de release exige indevidamente o sender do 2FA desabilitado'
fi
grep -Fq 'sender WhatsApp do 2FA deve permanecer ausente' \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'ausência do sender de 2FA não é validada'
grep -Fq 'smtp.resend.com:587' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'receptor Resend do Alertmanager ausente'
grep -Fq 'web.listen-address=127.0.0.1:9093' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'Alertmanager não está declarado somente em loopback'
grep -Fq 'BlindouSyntheticReceiverTest' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'teste sintético do receptor externo ausente'
grep -Fq 'confirm-offsite-backup)' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'recibo fechado de backup offsite ausente'
grep -Fq 'rpo_minutes=15' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'RPO aprovado não foi registrado'
grep -Fq 'rto_hours=4' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'RTO aprovado não foi registrado'
grep -Fq 'retention_days=30' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'retenção offsite aprovada não foi registrada'
grep -Fq 'activate-release-gates)' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'transição fechada dos gates ausente'
grep -Fq 'bootstrap-superadmin)' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'bootstrap fechado do superadmin ausente'
apply_release_function="$(sed -n '/^apply_release()/,/^}/p' \
  "${REMOTE_DIR}/blindou-deployctl")"
grep -Fq 'set +e' <<<"$apply_release_function" \
  && grep -Fq 'set -Eeuo pipefail' <<<"$apply_release_function" \
  && grep -Fq 'apply_status=$?' <<<"$apply_release_function" \
  && grep -Fq 'if (( apply_status != 0 )); then' <<<"$apply_release_function" \
  || fail 'apply não restaura errexit antes de decidir rollback'
if grep -Fq 'if ! apply_cached_release' <<<"$apply_release_function"; then
  fail 'apply ainda suprime errexit no corpo da release'
fi
grep -Fq "readonly SUPERADMIN_EMAIL='gleisonsette@gmail.com'" \
  "${REMOTE_DIR}/blindou-deployctl" || fail 'identidade fixa do superadmin ausente'
grep -Fq 'provision-runtime-secrets blindou-runtime-secrets' \
  "${REMOTE_DIR}/blindou-deployctl.sudoers" || fail 'sudoers não libera o provisionamento fechado'
grep -Fq 'provision-ui-review-runtime blindou-ui-review-runtime' \
  "${REMOTE_DIR}/blindou-deployctl.sudoers" || fail 'sudoers não libera a revisão da UI'
grep -Fq 'bootstrap-superadmin * blindou-bootstrap-superadmin' \
  "${REMOTE_DIR}/blindou-deployctl.sudoers" || fail 'sudoers não libera o bootstrap fechado'
grep -Fq "readonly GHCR_PULL_VERIFIER='/usr/local/lib/blindou-platform/blindou-ghcr-pull-verify.py'" \
  "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'verificador root-owned do pull GHCR ausente'
grep -Fq 'verify-ghcr-candidate-pull)' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'operação fechada de pull da candidata ausente'
grep -Fq 'python3 "$GHCR_PULL_VERIFIER"' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'pull GHCR não usa o verificador dedicado'
grep -Fq '| python3 "$GHCR_PULL_VERIFIER"' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'credencial GHCR não chega ao verificador por stdin'
grep -Fq 'verify-ghcr-candidate-pull *' "${REMOTE_DIR}/blindou-deployctl.sudoers" \
  || fail 'sudoers não libera somente a interface fechada de prova GHCR'
grep -Fq 'blindou_ghcr_candidate_pull_verified' "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'métrica da prova GHCR ausente'
grep -Fq 'GHCR_PULL_VERIFIER_SOURCE' "${REMOTE_DIR}/bootstrap-blindou-deployctl.sh" \
  || fail 'bootstrap não instala o verificador de pull GHCR'
grep -Fq 'urllib.request.ProxyHandler({})' "${REMOTE_DIR}/blindou-ghcr-pull-verify.py" \
  || fail 'verificador GHCR não desabilita proxy herdado'
grep -Fq 'redirected.remove_header("Authorization")' \
  "${REMOTE_DIR}/blindou-ghcr-pull-verify.py" \
  || fail 'redirect de blob pode encaminhar autorização a outro host'
grep -Fq 'TemporaryDirectory(prefix="blindou-ghcr-pull."' \
  "${REMOTE_DIR}/blindou-ghcr-pull-verify.py" \
  || fail 'bytes baixados não usam workspace temporário autoclean'
grep -Fq 'COMPONENTS = ("backend", "redirector", "nats", "cloudflared")' \
  "${REMOTE_DIR}/blindou-ghcr-pull-verify.py" \
  || fail 'prova GHCR não cobre exatamente as quatro imagens privadas'
grep -Fq "grep -Fxq 'images=4'" "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'recibo GHCR não exige exatamente quatro imagens privadas'
grep -Fq 'GHCR_PULL_SECRET = "blindou-ghcr-pull"' \
  "${REMOTE_DIR}/blindou-release-verify.py" || fail 'verificador não fixa o pull secret GHCR'
[[ "$(grep -Fc 'if ( verify_edge_connector >/dev/null 2>&1 ); then' \
  "${REMOTE_DIR}/blindou-deployctl")" == '1' ]] \
  || fail 'sondagem pré-release do conector precisa isolar falha esperada em subshell'
grep -Fq '|| ( verify_edge_connector >/dev/null 2>&1 ); then' \
  "${REMOTE_DIR}/blindou-deployctl" \
  || fail 'status do conector precisa aceitar o gate passed sem mascarar falha'
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
