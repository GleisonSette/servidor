#!/usr/bin/env python3
"""Valida offline a fundação e a interface fechada do controlador DRE."""

from __future__ import annotations

import pathlib
import re

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise SystemExit(f"[verify-dre-controller-artifacts] ERRO: {message}")


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file() or path.is_symlink():
        fail(f"arquivo ausente ou simbólico: {relative}")
    return path.read_text(encoding="utf-8")


def yaml_documents(relative: str) -> list[dict]:
    try:
        documents = [doc for doc in yaml.safe_load_all(read(relative)) if doc]
    except yaml.YAMLError as error:
        fail(f"YAML inválido em {relative}: {error}")
    if not documents or not all(isinstance(document, dict) for document in documents):
        fail(f"YAML vazio ou não estruturado: {relative}")
    return documents


def by_kind_name(documents: list[dict], kind: str, name: str) -> dict:
    matches = [
        document
        for document in documents
        if document.get("kind") == kind
        and document.get("metadata", {}).get("name") == name
    ]
    if len(matches) != 1:
        fail(f"{kind}/{name} ausente ou duplicado")
    return matches[0]


foundation = yaml_documents("platform/dre/controller-foundation.yaml")
production = by_kind_name(foundation, "Namespace", "dre-production")
edge = by_kind_name(foundation, "Namespace", "dre-edge")
restore = by_kind_name(foundation, "Namespace", "dre-restore-drill")
if any(
    document.get("kind") == "Namespace"
    and document.get("metadata", {}).get("name") == "dre-validation"
    for document in foundation
):
    fail("namespace descartável não pode permanecer na fundação")
for namespace in (production, edge, restore):
    labels = namespace["metadata"]["labels"]
    if labels.get("platform.servidor.local/project") != "dre":
        fail("namespace fora do ownership DRE")
    if labels.get("pod-security.kubernetes.io/enforce") != "restricted":
        fail("Pod Security restricted ausente")
    if labels.get("pod-security.kubernetes.io/enforce-version") != "v1.36":
        fail("versão Pod Security diverge")
if production["metadata"]["labels"].get("platform.servidor.local/deployment-gate") != "blocked":
    fail("namespace de produção deve nascer blocked")
if production["metadata"]["labels"].get("dre.familiar/lifecycle") != "always-active":
    fail("DRE não está declarado como sempre ativo")
if edge["metadata"]["labels"].get("platform.servidor.local/deployment-gate") != "blocked":
    fail("namespace de edge deve nascer bloqueado")
if edge["metadata"]["labels"].get("dre.familiar/api-access") != "true":
    fail("namespace de edge não possui acesso explícito à API")
if edge["metadata"]["labels"].get("dre.familiar/lifecycle") != "edge-connector":
    fail("lifecycle do edge diverge")
if "platform.servidor.local/secondary-slot-member" in production["metadata"]["labels"]:
    fail("DRE não pode integrar o slot APIWPP/SaferWPP")
if restore["metadata"]["labels"].get("platform.servidor.local/deployment-gate") != "restore-only":
    fail("namespace de restore não está fechado")

edge_quota = by_kind_name(foundation, "ResourceQuota", "dre-edge-quota")
edge_hard = edge_quota["spec"]["hard"]
if (
    edge_hard.get("pods") != "1"
    or edge_hard.get("services") != "0"
    or edge_hard.get("secrets") != "1"
    or edge_hard.get("persistentvolumeclaims") != "0"
    or edge_hard.get("count/deployments.apps") != "1"
):
    fail("quota do edge não limita exatamente um conector")
by_kind_name(foundation, "LimitRange", "dre-edge-defaults")
edge_account = by_kind_name(foundation, "ServiceAccount", "dre-cloudflared")
if edge_account.get("metadata", {}).get("namespace") != "dre-edge" or edge_account.get(
    "automountServiceAccountToken"
) is not False:
    fail("ServiceAccount do edge não está isolada")
edge_policies = {
    policy["metadata"]["name"]: policy
    for policy in foundation
    if policy.get("kind") == "NetworkPolicy"
    and policy.get("metadata", {}).get("namespace") == "dre-edge"
}
if set(edge_policies) != {
    "default-deny",
    "allow-cluster-dns",
    "allow-cloudflare-edge",
    "allow-dre-api-origin",
}:
    fail("NetworkPolicies do edge divergem")
cloudflare_ports = edge_policies["allow-cloudflare-edge"]["spec"]["egress"][0]["ports"]
if cloudflare_ports != [{"protocol": "TCP", "port": 7844}]:
    fail("edge permite saída pública além de TCP/7844")
origin_rule = edge_policies["allow-dre-api-origin"]["spec"]["egress"][0]
if origin_rule.get("ports") != [{"protocol": "TCP", "port": 8080}]:
    fail("edge permite porta de origem diferente da API")

retain = by_kind_name(foundation, "StorageClass", "dre-local-retain")
delete = by_kind_name(foundation, "StorageClass", "dre-local-delete-drill")
if retain.get("reclaimPolicy") != "Retain":
    fail("StorageClass de produção não usa Retain")
if delete.get("reclaimPolicy") != "Delete":
    fail("StorageClass de restore descartável não usa Delete")
for storage_class in (retain, delete):
    if storage_class.get("provisioner") != "rancher.io/local-path":
        fail("StorageClass não usa o provisionador local aprovado")

quota = by_kind_name(foundation, "ResourceQuota", "dre-restore-drill-quota")
hard = quota["spec"]["hard"]
if hard.get("persistentvolumeclaims") != "1" or hard.get("requests.storage") != "24Gi":
    fail("quota do restore não limita PVC e storage")
policies = [
    document
    for document in foundation
    if document.get("kind") == "NetworkPolicy"
    and document.get("metadata", {}).get("namespace") == "dre-restore-drill"
]
if {policy["metadata"]["name"] for policy in policies} != {
    "default-deny",
    "allow-cluster-dns",
    "allow-r2-https",
}:
    fail("NetworkPolicies do restore divergem")

cluster_binding = by_kind_name(foundation, "ClusterRoleBinding", "dre-deployctl-cluster")
if cluster_binding.get("subjects") != [
    {"apiGroup": "rbac.authorization.k8s.io", "kind": "User", "name": "dre-deployctl"}
]:
    fail("ClusterRoleBinding não usa a identidade exclusiva DRE")
cluster_role = by_kind_name(foundation, "ClusterRole", "dre-deployctl-cluster")
namespace_rule = next(
    (
        rule
        for rule in cluster_role.get("rules", [])
        if "namespaces" in rule.get("resources", [])
    ),
    None,
)
if namespace_rule is None or set(namespace_rule.get("resourceNames", [])) != {
    "dre-production",
    "dre-edge",
    "dre-restore-drill",
    "dre-validation",
}:
    fail("ClusterRole não limita os quatro namespaces DRE")
for rule in cluster_role.get("rules", []):
    if "secrets" in rule.get("resources", []) or "pods/exec" in rule.get("resources", []):
        fail("ClusterRole DRE ganhou acesso mutável global")

edge_role_matches = [
    document
    for document in foundation
    if document.get("kind") == "Role"
    and document.get("metadata", {}).get("name") == "dre-deployctl"
    and document.get("metadata", {}).get("namespace") == "dre-edge"
]
if len(edge_role_matches) != 1:
    fail("Role fechada do edge ausente ou duplicada")
edge_role = edge_role_matches[0]
edge_resources = {
    resource
    for rule in edge_role.get("rules", [])
    for resource in rule.get("resources", [])
}
if edge_resources != {"secrets", "deployments", "pods"}:
    fail("RBAC do edge ganhou recurso não autorizado")
edge_named_rules = [
    rule
    for rule in edge_role.get("rules", [])
    if "resourceNames" in rule
]
if {tuple(rule["resourceNames"]) for rule in edge_named_rules} != {
    ("dre-cloudflare-tunnel",),
    ("dre-cloudflared",),
}:
    fail("RBAC de mutação do edge não está preso aos recursos aprovados")
secret_rule = next(
    rule for rule in edge_named_rules if rule["resourceNames"] == ["dre-cloudflare-tunnel"]
)
if set(secret_rule.get("verbs", [])) != {"delete", "get", "patch", "update"}:
    fail("RBAC do token do túnel ganhou leitura ampla ou operação desnecessária")
deployment_rule = next(
    rule for rule in edge_named_rules if rule["resourceNames"] == ["dre-cloudflared"]
)
if set(deployment_rule.get("verbs", [])) != {"delete", "get", "patch", "update", "watch"}:
    fail("RBAC do Deployment do edge diverge")
edge_binding_matches = [
    document
    for document in foundation
    if document.get("kind") == "RoleBinding"
    and document.get("metadata", {}).get("name") == "dre-deployctl"
    and document.get("metadata", {}).get("namespace") == "dre-edge"
]
if len(edge_binding_matches) != 1 or edge_binding_matches[0].get("subjects") != [
    {"apiGroup": "rbac.authorization.k8s.io", "kind": "User", "name": "dre-deployctl"}
]:
    fail("RoleBinding do edge não usa a identidade DRE")

edge_runtime = yaml_documents("platform/dre/edge-runtime.yaml")
if len(edge_runtime) != 1:
    fail("runtime do edge deve conter somente um Deployment")
edge_deployment = by_kind_name(edge_runtime, "Deployment", "dre-cloudflared")
if edge_deployment.get("metadata", {}).get("namespace") != "dre-edge":
    fail("cloudflared saiu do namespace de edge")
pod_spec = edge_deployment["spec"]["template"]["spec"]
if pod_spec.get("automountServiceAccountToken") is not False:
    fail("cloudflared permite token automático da ServiceAccount")
containers = pod_spec.get("containers", [])
if len(containers) != 1:
    fail("edge deve conter exatamente um container")
cloudflared = containers[0]
if cloudflared.get("image") != (
    "docker.io/cloudflare/cloudflared@sha256:"
    "18626b1baac4450214535cd5bc40ef44c0635244d585ebf707749c22b6f3408f"
):
    fail("imagem cloudflared não está fixada no digest aprovado")
if cloudflared.get("args") != [
    "tunnel",
    "--no-autoupdate",
    "--protocol",
    "http2",
    "--metrics",
    "0.0.0.0:20241",
    "run",
    "--token-file",
    "/etc/cloudflared/token",
]:
    fail("argumentos fechados do cloudflared divergem")
security = cloudflared.get("securityContext", {})
if (
    security.get("allowPrivilegeEscalation") is not False
    or security.get("readOnlyRootFilesystem") is not True
    or security.get("capabilities", {}).get("drop") != ["ALL"]
):
    fail("container cloudflared não usa o baseline restrito")

validation_access = yaml_documents("platform/dre/validation-access.yaml")
validation_role = by_kind_name(validation_access, "Role", "dre-deployctl")
validation_binding = by_kind_name(validation_access, "RoleBinding", "dre-deployctl")
for resource in (validation_role, validation_binding):
    if resource.get("metadata", {}).get("namespace") != "dre-validation":
        fail("RBAC descartável saiu de dre-validation")
if validation_binding.get("subjects") != [
    {"apiGroup": "rbac.authorization.k8s.io", "kind": "User", "name": "dre-deployctl"}
]:
    fail("RoleBinding descartável não usa a identidade DRE")
validation_resources = {
    resource
    for rule in validation_role.get("rules", [])
    for resource in rule.get("resources", [])
}
for required in ("pods", "pods/exec", "services/proxy", "jobs", "statefulsets"):
    if required not in validation_resources:
        fail(f"RBAC descartável não permite o recurso fechado: {required}")

admission = by_kind_name(foundation, "ValidatingAdmissionPolicy", "dre-controller-only")
if admission.get("spec", {}).get("failurePolicy") != "Fail":
    fail("admissão DRE não falha fechada")
validation_text = "\n".join(
    str(validation.get("expression", ""))
    for validation in admission.get("spec", {}).get("validations", [])
)
for invariant in (
    "request.userInfo.username == 'dre-deployctl'",
    "system:kube-controller-manager",
    "request.userInfo.username == 'system:kube-scheduler'",
    "request.operation == 'UPDATE'",
    "request.resource.resource == 'persistentvolumeclaims'",
    "system:serviceaccount:kube-system:",
):
    if invariant not in validation_text:
        fail(f"invariante de admissão ausente: {invariant}")
match_condition_text = "\n".join(
    str(condition.get("expression", ""))
    for condition in admission.get("spec", {}).get("matchConditions", [])
)
if "dre-validation" not in match_condition_text:
    fail("admissão não protege dre-validation")

controller = read("operations/remote/dre-deployctl")
for invariant in (
    "readonly NAMESPACE='dre-production'",
    "readonly EDGE_NAMESPACE='dre-edge'",
    "readonly EDGE_RUNTIME='/usr/local/lib/dre-deployctl/edge-runtime.yaml'",
    "readonly EDGE_CONNECTOR_IMAGE='docker.io/cloudflare/cloudflared@sha256:",
    "readonly RESTORE_NAMESPACE='dre-restore-drill'",
    "readonly VALIDATION_NAMESPACE='dre-validation'",
    "readonly VALIDATION_MATERIAL='/usr/local/lib/dre-deployctl/dre-validation-material.py'",
    "readonly VALIDATION_ACCESS='/usr/local/lib/dre-deployctl/validation-access.yaml'",
    "readonly MIN_AVAILABLE_MEMORY_KIB=$((5 * 1024 * 1024))",
    "readonly MIN_AVAILABLE_DISK_KIB=$((45 * 1024 * 1024))",
    "readonly PLAN_RETENTION_DAYS=7",
    "printf '%s %s %s\\n' \"$memory_available\" \"$disk_available\" \"$cpu_count\"",
    "openssl pkeyutl -verify -pubin",
    "verify_cached_release_again",
    "verify_release_secret_inventory",
    "require_new_receipt",
    "provision_accounts",
    "configure_edge",
    "rollback_edge_connector_internal",
    "verify_edge_connector_runtime",
    'admin_kube -n "$EDGE_NAMESPACE" get deployment,secret -o json',
    '(.items | length) <= 1',
    '.metadata.name == "kube-root-ca.crt"',
    '((.data // {}) | keys) == ["ca.crt"]',
    'startswith("-----BEGIN CERTIFICATE-----")',
    '((.binaryData // {}) | length) == 0',
    "edge contém ConfigMap diferente da CA sistêmica do Kubernetes",
    "--from-file=token=/dev/stdin",
    "token_persisted_only_in_kubernetes:true",
    "dre_controller_edge_expected",
    "dre_controller_edge_ready",
    "/app/dre-admin-cli provision-private-family",
    "--passwords-stdin",
    "atomic:true",
    "deployment-gate=rollback-failed",
    'status:"started"',
    "verify_protected_projects",
    "release_shared_maintenance_locks",
    "/usr/local/sbin/blindou-deployctl status",
    "protected_fingerprint",
    "occupant=(none|apiwpp|saferwpp)",
    "slot none possui workload ativo",
    "namespaces+=(\"$namespace\")",
    "readonly BLINDOU_DATA_LOCK='/run/lock/blindou-datactl.lock'",
    "namespaces+=(blindou-data)",
    "secondary_slot_member:false",
    'bridge_token_source:"orchestrator-stdin"',
    "generic_shell:false",
    "generic_kubectl:false",
    "dre-pgbackrest stanza-create",
    "dre-pgbackrest check",
    "restore-drill",
    "validate-release",
    "cleanup-validation",
    "diagnose-validation",
    "register_exit_trap",
    "register_exit_trap rollback_secret_creation",
    "register_exit_trap validation_failed",
    "register_exit_trap cleanup_validation_failed",
    "register_exit_trap deploy_failed",
    "register_exit_trap backup_failed",
    "register_exit_trap restore_failed",
    "require_schema_two_release",
    "require_validation_receipt",
    "validation_cleanup_internal",
    "restart_validation_component api",
    "restart_validation_component worker",
    "restart_validation_component postgres",
    "wait_for_job_completion",
    "Job ${job} falhou: ${reason}",
    "--limit-bytes=16384",
    "pod_ip:(.status.podIP // null)",
    "sanitize_diagnostic_output",
    "postgres_diagnostics",
    "service_state",
    "/usr/local/bin/pg_isready",
    "127.0.0.1",
    "[redacted]",
    'release_schemas:{import:[1,2],deploy:[2],rollback:[1,2]}',
    "StorageClass Delete",
    "prune_expired_plans",
    'backup_timestamp="${backup_timestamp:-0}"',
    'restore_timestamp="${restore_timestamp:-0}"',
    "valor interno de métrica DRE inválido",
):
    if invariant not in controller:
        fail(f"invariante do controlador ausente: {invariant}")
for forbidden in ("eval ", "bash -c", "sh -c", "kubectl $", "sudo -S"):
    if forbidden in controller:
        fail(f"interface genérica detectada no controlador: {forbidden}")
if "/usr/local/sbin/blindou-deployctl verify " in controller:
    fail("controlador DRE chama ação Blindou inexistente")
if "get statefulset,daemonset,job,cronjob,service,pvc,configmap" in controller:
    fail("CA sistêmica do namespace voltou a ser tratada como objeto proibido genérico")
if 'kube -n "$EDGE_NAMESPACE" get deployment,secret -o json' in controller.replace(
    'admin_kube -n "$EDGE_NAMESPACE" get deployment,secret -o json', ""
):
    fail("inventário vazio do edge usa identidade sem permissão de listagem")

for function_name in (
    "validate_release_disposable",
    "cleanup_validation",
    "deploy_release",
    "configure_edge",
    "provision_accounts",
):
    function_match = re.search(
        rf"(?ms)^{function_name}\(\) \{{.*?(?=^[a-z_][a-z0-9_]*\(\) \{{)",
        controller,
    )
    if function_match is None:
        fail(f"função do controlador ausente: {function_name}")
    function = function_match.group(0)
    acquire = function.find("acquire_shared_maintenance_locks")
    release = function.find("release_shared_maintenance_locks")
    final_gate = function.find("verify_protected_projects", acquire)
    if acquire < 0 or release < 0 or final_gate < 0 or not acquire < release < final_gate:
        fail(
            f"{function_name} chama controlador protegido enquanto ainda mantém seus locks"
        )

release_verifier = read("operations/remote/dre-release-verify.py")
for invariant in (
    '"40-validation-platform.yaml"',
    '"45-validation-e2e.yaml"',
    '"validation_namespace"',
    'release.get("migration_count") != 9',
    '"sbom/validation.spdx.json"',
    '"scan/validation.json"',
):
    if invariant not in release_verifier:
        fail(f"contrato schema 2 ausente no verificador de release: {invariant}")

sudoers = read("operations/remote/dre-deployctl.sudoers")
lines = [line for line in sudoers.splitlines() if line.startswith("apiadmin ")]
allowed_actions = {
    "contract",
    "status",
    "diagnose-validation",
    "import-release *",
    "initialize-secrets *",
    "validate-release *",
    "cleanup-validation *",
    "plan *",
    "deploy *",
    "verify *",
    "configure-edge *",
    "provision-accounts *",
    "backup *",
    "restore-drill *",
}
actual_actions = {
    line.split("/usr/local/sbin/dre-deployctl ", 1)[1] for line in lines
}
if actual_actions != allowed_actions:
    fail("sudoers DRE diverge da interface fechada")
if "SETENV" in sudoers or " /bin/" in sudoers or " /usr/bin/" in sudoers:
    fail("sudoers DRE concede ambiente ou comando genérico")

for unsafe_trap in (
    "trap rollback_secret_creation EXIT",
    "trap validation_failed EXIT",
    "trap cleanup_validation_failed EXIT",
    "trap deploy_failed EXIT",
    "trap backup_failed EXIT",
    "trap restore_failed EXIT",
):
    if unsafe_trap in controller:
        fail(f"trap EXIT sem contexto preservado: {unsafe_trap}")

bootstrap = read("operations/remote/bootstrap-dre-deployctl.sh")
for invariant in (
    "verify-dre-controller-artifacts.py",
    "PUBLIC_KEY_SHA256",
    "ED25519 Public-Key",
    "apiwpp-deployctl verify",
    "blindou-deployctl status",
    "secondary-slotctl verify",
    '.bridge_token_source == "orchestrator-stdin"',
    "--as=dre-untrusted",
    "dre-kube-identityctl reconcile",
    "/etc/dre-deployctl/client.key",
    "/var/lib/prometheus/node-exporter/dre-controller.prom",
    "promtool check config",
    "promtool check metrics",
    'logrotate --debug "$LOGROTATE_SOURCE"',
    "rollback_needed=true",
    "trap rollback EXIT",
    "require_production_predeploy_state",
    "require_empty_namespace dre-restore-drill",
    "require_validation_namespace_absent",
    "require_validation_bootstrap_state",
    "validation_configuration_fingerprint",
    "configuração da validação bloqueada mudou durante o bootstrap",
    "production_gate_before='blocked'",
    "production_secret_count=0",
    '|| "$production_secret_count" -ge 5',
    "platform.servidor.local/deployment-gate=secrets-only",
    "dre-validation-material.py",
    "validation-access.yaml",
    "edge-runtime.yaml",
    "require_edge_bootstrap_state",
    'edge_namespace == "dre-edge"',
    'index("configure-edge")',
    'for resource in "${resources[@]}"',
    "--ignore-not-found -o name | wc -l",
    "wait_for_protected_locks_release",
    "/run/lock/apiwpp-deploy.lock",
    "flock --timeout 90",
    "lock protegido não foi liberado em 90 segundos",
    "run_protected_gate",
    "run_secondary_slot_gate",
    "occupant=(none|apiwpp|saferwpp)",
    "slot none possui workload ativo",
    "another apiwpp deployment is already running",
    "outra operação Blindou está em andamento",
    "permaneceu ocupado por 60 segundos",
    "PLATFORM_BOOTSTRAP_LOCK='/run/lock/servidor-local-platform-bootstrap.lock'",
    "flock --nonblock 6",
    "flock --unlock 6",
    "flock --timeout 30 6",
    "rollback não readquiriu o lock global",
    "reset_dre_unit_failures",
    'systemctl reset-failed "$unit"',
):
    if invariant not in bootstrap:
        fail(f"gate do bootstrap ausente: {invariant}")
blindou_checks = [
    index
    for index, line in enumerate(bootstrap.splitlines())
    if line.startswith("run_protected_gate Blindou ")
]
slot_checks = [
    index
    for index, line in enumerate(bootstrap.splitlines())
    if line == "run_secondary_slot_gate"
]
if (
    len(blindou_checks) != 2
    or len(slot_checks) != 2
    or any(blindou >= slot for blindou, slot in zip(blindou_checks, slot_checks))
):
    fail("ordem dos gates protegidos não evita herança transitória do lock Blindou")

sudo_helper = read("operations/Dre.SudoBootstrap.psm1")
for invariant in (
    "KEY_SERVIDOR=",
    "apiadmin@192.168.100.59",
    "dre-controller-bootstrap-",
    "sudo -S -p '' -- /bin/bash -c",
    "/var/lib/servidor-local/bootstrap-releases/dre-controller",
    "flock --unlock 9",
    "ExpectedArchiveSha256",
    "PublicKeySha256",
    "BatchMode=yes",
    "C:\\github\\servidor\\.env",
):
    if invariant not in sudo_helper:
        fail(f"proteção do helper sudo DRE ausente: {invariant}")
for forbidden in ("Invoke-Expression", "Start-Process", "Write-Host $password"):
    if forbidden in sudo_helper:
        fail(f"helper sudo DRE contém operação proibida: {forbidden}")
if "Join-Path $repositoryRoot '.env'" in sudo_helper:
    fail("helper sudo DRE ainda depende do worktree para localizar .env")

logrotate = read("operations/remote/dre-deployctl.logrotate")
for invariant in (
    "/var/lib/dre-deployctl/audit.jsonl",
    "daily",
    "rotate 30",
    "maxsize 16M",
    "create 0600 root root",
):
    if invariant not in logrotate:
        fail(f"retenção do audit log ausente: {invariant}")

identity = read("operations/remote/dre-kube-identityctl")
for invariant in (
    "/CN=dre-deployctl/O=dre-deployers",
    "extendedKeyUsage=clientAuth",
    "RENEW_BEFORE_SECONDS=$((45 * 24 * 60 * 60))",
    'index("system:masters")',
    "-days 365",
    '"$0" verify',
):
    if invariant not in identity:
        fail(f"contrato da identidade ausente: {invariant}")

restore_renderer = read("operations/remote/dre-restore-render.py")
for invariant in (
    'NAMESPACE = "dre-restore-drill"',
    '"storageClassName": "dre-local-delete-drill"',
    '"archive_mode=off"',
    '"archive_command=/bin/false"',
    '"DRE_RESTORE_CONFIRM", "value": "DISPOSABLE_RESTORE"',
):
    if invariant not in restore_renderer:
        fail(f"proteção de restore ausente: {invariant}")

secret_material = read("operations/remote/dre-secret-material.py")
for invariant in (
    '"web_bridge_token"',
    "BRIDGE_TOKEN_MIN_LENGTH = 64",
    'write_secret(output, "api-runtime/web-bridge-token", bridge_token)',
):
    if invariant not in secret_material:
        fail(f"contrato coordenado do token da ponte ausente: {invariant}")
if 'write_secret(output, "api-runtime/web-bridge-token", generate_secret' in secret_material:
    fail("token da ponte ainda é gerado sem coordenação com o Cloudflare")

validation_material = read("operations/remote/dre-validation-material.py")
for invariant in (
    'LOGIN_HOST = "dre-postgres.dre-validation.svc.cluster.local"',
    '"validation-accounts/primary-password"',
    '"validation-accounts/secondary-password"',
    "allowed_registries",
    "dre_validation_material=passed synthetic=true",
):
    if invariant not in validation_material:
        fail(f"contrato do material sintético ausente: {invariant}")

alerts = yaml_documents("platform/dre/monitoring/prometheus-alerts.yaml")
alert_names = {
    rule["alert"]
    for group in alerts[0].get("groups", [])
    for rule in group.get("rules", [])
}
if alert_names != {
    "DreControllerFoundationUnavailable",
    "DreControllerReleaseUnavailable",
    "DreControllerEdgeUnavailable",
    "DreControllerBackupStale",
    "DreControllerRestoreDrillStale",
    "DreControllerIdentityExpiring",
}:
    fail("alertas do controlador DRE divergem")

artifact_files = [
    path
    for path in (ROOT / "platform" / "dre").rglob("*")
    if path.is_file()
]
artifact_files.extend(
    ROOT / "operations" / "remote" / name
    for name in (
        "dre-deployctl",
        "dre-deployctl.sudoers",
        "dre-deployctl.logrotate",
        "dre-kube-identityctl",
        "dre-kube-identity.service",
        "dre-kube-identity.timer",
        "dre-controller-metrics.service",
        "dre-controller-metrics.timer",
        "dre-release-verify.py",
        "dre-secret-material.py",
        "dre-validation-material.py",
        "dre-restore-render.py",
        "bootstrap-dre-deployctl.sh",
    )
)
secret_pattern = re.compile(
    r"BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY|"
    r"(?i:(?:password|token|secret|private[_-]?key)\s*[:=]\s*['\"][A-Za-z0-9+_.-][A-Za-z0-9/+_.-]{15,}['\"])"
)
for path in artifact_files:
    if secret_pattern.search(path.read_text(encoding="utf-8")):
        fail(f"possível segredo encontrado em {path.relative_to(ROOT)}")

print("dre_controller_artifacts=passed")
