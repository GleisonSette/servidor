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
restore = by_kind_name(foundation, "Namespace", "dre-restore-drill")
if any(
    document.get("kind") == "Namespace"
    and document.get("metadata", {}).get("name") == "dre-validation"
    for document in foundation
):
    fail("namespace descartável não pode permanecer na fundação")
for namespace in (production, restore):
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
if "platform.servidor.local/secondary-slot-member" in production["metadata"]["labels"]:
    fail("DRE não pode integrar o slot APIWPP/SaferWPP")
if restore["metadata"]["labels"].get("platform.servidor.local/deployment-gate") != "restore-only":
    fail("namespace de restore não está fechado")

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
    "dre-restore-drill",
    "dre-validation",
}:
    fail("ClusterRole não limita os três namespaces DRE")
for rule in cluster_role.get("rules", []):
    if "secrets" in rule.get("resources", []) or "pods/exec" in rule.get("resources", []):
        fail("ClusterRole DRE ganhou acesso mutável global")

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
    "readonly RESTORE_NAMESPACE='dre-restore-drill'",
    "readonly VALIDATION_NAMESPACE='dre-validation'",
    "readonly VALIDATION_MATERIAL='/usr/local/lib/dre-deployctl/dre-validation-material.py'",
    "readonly VALIDATION_ACCESS='/usr/local/lib/dre-deployctl/validation-access.yaml'",
    "readonly MIN_AVAILABLE_MEMORY_KIB=$((5 * 1024 * 1024))",
    "readonly MIN_AVAILABLE_DISK_KIB=$((45 * 1024 * 1024))",
    "readonly PLAN_RETENTION_DAYS=7",
    "openssl pkeyutl -verify -pubin",
    "verify_cached_release_again",
    "verify_release_secret_inventory",
    "require_new_receipt",
    "deployment-gate=rollback-failed",
    'status:"started"',
    "verify_protected_projects",
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
    "require_schema_two_release",
    "require_validation_receipt",
    "validation_cleanup_internal",
    "restart_validation_component api",
    "restart_validation_component worker",
    "restart_validation_component postgres",
    'release_schemas:{import:[1,2],deploy:[2],rollback:[1,2]}',
    "StorageClass Delete",
    "prune_expired_plans",
    'backup_timestamp="${backup_timestamp:-0}"',
    'restore_timestamp="${restore_timestamp:-0}"',
    "valor interno de métrica DRE inválido",
    "trap rollback_secret_creation EXIT",
    "trap deploy_failed EXIT",
    "trap backup_failed EXIT",
    "trap restore_failed EXIT",
):
    if invariant not in controller:
        fail(f"invariante do controlador ausente: {invariant}")
for forbidden in ("eval ", "bash -c", "sh -c", "kubectl $", "sudo -S"):
    if forbidden in controller:
        fail(f"interface genérica detectada no controlador: {forbidden}")
if "/usr/local/sbin/blindou-deployctl verify " in controller:
    fail("controlador DRE chama ação Blindou inexistente")

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
    "import-release *",
    "initialize-secrets *",
    "validate-release *",
    "cleanup-validation *",
    "plan *",
    "deploy *",
    "verify *",
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
    "production_gate_before='blocked'",
    "production_secret_count=0",
    '|| "$production_secret_count" -ge 5',
    "platform.servidor.local/deployment-gate=secrets-only",
    "dre-validation-material.py",
    "validation-access.yaml",
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
