#!/usr/bin/env python3
"""Valida offline o contrato compartilhado do slot alternável."""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise SystemExit(f"[verify-secondary-slot-artifacts] ERRO: {message}")


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file() or path.is_symlink():
        fail(f"arquivo ausente ou simbólico: {relative}")
    return path.read_text(encoding="utf-8")


def yaml_documents(relative: str) -> list[dict]:
    documents = [document for document in yaml.safe_load_all(read(relative)) if document]
    if not documents or not all(isinstance(document, dict) for document in documents):
        fail(f"YAML vazio ou inválido: {relative}")
    return documents


def require_equal(actual: object, expected: object, description: str) -> None:
    if actual != expected:
        fail(f"{description}: esperado {expected!r}, obtido {actual!r}")


contract = yaml_documents("platform/secondary-slot/contract.yaml")
require_equal(len(contract), 1, "quantidade de contratos")
spec = contract[0]["spec"]
require_equal(spec["schema"], 1, "schema")
require_equal(spec["slot"], "secondary", "slot")
require_equal(
    spec["stateFile"],
    "/var/lib/servidor-local/secondary-slot/state",
    "fonte de verdade",
)
require_equal(
    spec["auditFile"],
    "/var/log/servidor-local/secondary-slot/audit.jsonl",
    "arquivo de auditoria",
)
require_equal(
    spec["globalLock"],
    "/run/lock/servidor-local-secondary-slot.lock",
    "lock global",
)
require_equal(
    spec["localEventRetention"],
    {"fileSizeMi": 16, "rotations": 5},
    "retenção local de auditoria e alertas",
)
require_equal(
    spec["stateHistoryRetention"],
    {"maxSnapshots": 256},
    "retenção do histórico de estados",
)
require_equal(
    spec["unresolvedAlertState"],
    "/var/lib/servidor-local/secondary-slot/unresolved-alerts.json",
    "estado compacto de alertas",
)
require_equal(
    spec["members"]["apiwpp"]["activeRuntime"],
    {
        "kind": "Deployment",
        "name": "apiwpp",
        "replicas": 1,
        "podSelector": "app.kubernetes.io/name=apiwpp,app.kubernetes.io/component=runtime",
    },
    "runtime APIWPP",
)
require_equal(
    spec["members"]["saferwpp"]["namespaces"],
    ["saferwpp-lab", "saferdock-identity", "saferdock-platform"],
    "namespaces SaferWPP",
)
require_equal(
    spec["members"]["saferwpp"]["activationReadiness"],
    {
        "longRunningWorkloadRequiredInEveryNamespace": True,
        "allActiveWorkloadsMustBeHealthy": True,
    },
    "readiness SaferWPP",
)
require_equal(spec["ownership"]["writerUser"], "root", "writer root-only")
require_equal(spec["ownership"]["fileMode"], "0600", "modo do atestado")
require_equal(spec["ownership"]["blindouResourcesMutable"], False, "imutabilidade Blindou")
require_equal(spec["transitions"]["ambiguousRuntimeFailsClosed"], True, "ambiguidade fechada")
require_equal(spec["transitions"]["stuckAfterSeconds"], 900, "limite de transição pendente")
require_equal(
    spec["transitions"]["unambiguousRuntimeCanBeReconciled"],
    True,
    "reconciliação inequívoca",
)
require_equal(
    spec["transitions"]["explicitReconciliationRepairsAdmissionDrift"],
    True,
    "reparo explícito da admissão",
)
require_equal(
    spec["transitions"]["auditEveryOutcomeAfterLockAcquisition"],
    True,
    "auditoria sob o lock global",
)
require_equal(
    spec["namespaceGate"]["installedPolicyMustMatchRootOwnedManifest"],
    True,
    "integridade da admissão instalada",
)

admission = yaml_documents("platform/secondary-slot/admission.yaml")
kinds_and_names = {
    (document.get("kind"), document.get("metadata", {}).get("name"))
    for document in admission
}
require_equal(
    kinds_and_names,
    {
        ("ValidatingAdmissionPolicy", "secondary-slot-inactive-workloads"),
        ("ValidatingAdmissionPolicyBinding", "secondary-slot-inactive-workloads"),
        ("ValidatingAdmissionPolicyBinding", "secondary-slot-uninitialized-workloads"),
    },
    "recursos de admissão",
)
policy = next(document for document in admission if document["kind"] == "ValidatingAdmissionPolicy")
require_equal(policy["spec"]["failurePolicy"], "Fail", "failurePolicy")
protected_resources = {
    resource
    for rule in policy["spec"]["matchConstraints"]["resourceRules"]
    for resource in rule["resources"]
}
require_equal(
    protected_resources,
    {
        "deployments",
        "statefulsets",
        "daemonsets",
        "replicasets",
        "replicationcontrollers",
        "jobs",
        "cronjobs",
        "pods",
    },
    "recursos protegidos pela admissão",
)
expressions = "\n".join(
    validation["expression"] for validation in policy["spec"]["validations"]
)
for resource in (
    "deployments",
    "statefulsets",
    "daemonsets",
    "replicasets",
    "replicationcontrollers",
    "jobs",
    "cronjobs",
    "pods",
):
    if resource not in expressions:
        fail(f"admissão não protege {resource}")
if "object.spec.replicas == 0" not in expressions:
    fail("admissão não força réplica zero em controladores escaláveis")
if "object.spec.suspend == true" not in expressions:
    fail("admissão não força suspensão de Jobs/CronJobs")
bindings = {
    document["metadata"]["name"]: document
    for document in admission
    if document["kind"] == "ValidatingAdmissionPolicyBinding"
}
for name, operator in (
    ("secondary-slot-inactive-workloads", "NotIn"),
    ("secondary-slot-uninitialized-workloads", "DoesNotExist"),
):
    binding = bindings[name]
    require_equal(binding["spec"]["policyName"], "secondary-slot-inactive-workloads", f"policyName de {name}")
    require_equal(binding["spec"]["validationActions"], ["Deny"], f"ação de {name}")
    expressions_by_key = {
        expression["key"]: expression
        for expression in binding["spec"]["matchResources"]["namespaceSelector"]["matchExpressions"]
    }
    require_equal(
        expressions_by_key["platform.servidor.local/secondary-slot-member"]["operator"],
        "Exists",
        f"membership de {name}",
    )
    require_equal(
        expressions_by_key["platform.servidor.local/secondary-slot-state"]["operator"],
        operator,
        f"estado de {name}",
    )
    state_expression = expressions_by_key[
        "platform.servidor.local/secondary-slot-state"
    ]
    expected_values = ["active"] if operator == "NotIn" else None
    require_equal(
        state_expression.get("values"),
        expected_values,
        f"valores do estado de {name}",
    )

for relative in (
    "platform/base/namespaces.yaml",
    "platform/saferwpp/00-platform-namespaces.yaml",
):
    for document in yaml_documents(relative):
        metadata = document.get("metadata", {})
        if document.get("kind") != "Namespace" or metadata.get("name") not in {
            "saferwpp-lab",
            "saferdock-identity",
            "saferdock-platform",
        }:
            continue
        labels = metadata.get("labels", {})
        require_equal(
            labels.get("platform.servidor.local/secondary-slot-member"),
            "saferwpp",
            f"membership de {metadata['name']}",
        )
        if "platform.servidor.local/secondary-slot-state" in labels:
            fail(f"manifesto estático não pode controlar o gate dinâmico de {metadata['name']}")

alerts = yaml_documents("platform/secondary-slot/monitoring/prometheus-alerts.yaml")
alert_names = {
    rule["alert"]
    for group in alerts[0]["groups"]
    for rule in group["rules"]
}
require_equal(
    alert_names,
    {
        "SecondarySlotSplitBrain",
        "SecondarySlotNeedsReconciliation",
        "SecondarySlotTransitionStuck",
        "SecondarySlotUnresolvedOperationalAlert",
        "SecondarySlotMetricsStale",
    },
    "alertas do slot",
)
reconciliation_alert = next(
    rule
    for group in alerts[0]["groups"]
    for rule in group["rules"]
    if rule["alert"] == "SecondarySlotNeedsReconciliation"
)
for metric in (
    "secondary_slot_state_valid",
    "secondary_slot_state_matches_runtime",
    "secondary_slot_namespace_gates_match",
    "secondary_slot_admission_matches",
):
    if metric not in reconciliation_alert["expr"]:
        fail(f"alerta de reconciliação não observa {metric}")

controller = read("operations/remote/secondary-slotctl")
library = read("operations/remote/secondary_slot.py")
sudoers = read("operations/remote/secondary-slotctl.sudoers")
bootstrap = read("operations/remote/bootstrap-secondary-slotctl.sh")
tmpfiles = read("operations/remote/secondary-slot-tmpfiles.conf")
sudo_bootstrap = read("operations/SecondarySlot.SudoBootstrap.psm1")
orchestrator = read("operations/Invoke-SecondarySlotBootstrap.ps1")
for invariant in (
    "/run/lock/servidor-local-secondary-slot.lock",
    "/var/lib/servidor-local/secondary-slot",
    "initialize-apiwpp-active",
    "begin-suspend",
    "complete-suspend",
    "reserve",
    "complete-activation",
    "abort-transition",
    "reconcile",
    "require_blindou_healthy_and_fingerprint",
    "transition-needs-reconciliation",
):
    if invariant not in controller:
        fail(f"invariante ausente no controlador: {invariant}")
for invariant in (
    "STATE_KEYS",
    "parse_exact_key_values",
    "active_occupant",
    "apiwpp_workloads",
    "saferwpp_workloads",
    "workload_is_active",
    "namespace_gates_match",
    "saferwpp_required_namespaces_active",
    "STATE_HISTORY_MAX_FILES",
    "textfile_directory_metadata_is_safe",
):
    if invariant not in library:
        fail(f"invariante ausente na biblioteca: {invariant}")
if "apiadmin ALL=(root) NOPASSWD" not in sudoers:
    fail("sudoers não limita a identidade operacional")
if re.search(r"secondary-slotctl\s+\*\s*(?:,|$)", sudoers, re.MULTILINE):
    fail("sudoers contém execução totalmente aberta")
if "python3 \"$VERIFIER_SOURCE\"" not in bootstrap:
    fail("bootstrap não executa o verificador offline")
if "promtool check config" not in bootstrap or "visudo -cf" not in bootstrap:
    fail("bootstrap não valida Prometheus e sudoers")
for invariant in (
    "METRICS_TARGET='/var/lib/prometheus/node-exporter/secondary-slot.prom'",
    'direct_metrics_output="$("$CONTROLLER_TARGET" metrics 2>&1)"',
    "--property=ExecMainStatus",
    "systemctl reset-failed secondary-slot-metrics.service",
    "coleta de métricas não liberou o lock em trinta segundos",
):
    if invariant not in bootstrap:
        fail(f"diagnóstico ou rollback de métricas ausente: {invariant}")
require_equal(
    tmpfiles,
    "f /run/lock/servidor-local-secondary-slot.lock 0600 root root -\n",
    "contrato tmpfiles do lock global",
)
if "O_NOFOLLOW" not in controller or "metadata.st_nlink != 1" not in controller:
    fail("controlador não protege o lock contra symlink ou hard link")
if "secondary_slot_admission_matches" not in controller:
    fail("métricas não atestam a integridade da admissão")
for invariant in (
    'pwd.getpwnam("prometheus")',
    'grp.getgrnam("prometheus")',
    "textfile_directory_metadata_is_safe",
):
    if invariant not in controller:
        fail(f"validação do textfile collector ausente: {invariant}")

for invariant in (
    "apiadmin@192.168.100.59",
    "saferwpp-secondary-slot-bootstrap-",
    "/var/lib/servidor-local/bootstrap-releases/secondary-slot",
    "servidor-local-platform-bootstrap.lock",
    "sha256sum",
    "apiadmin:apiadmin:600:1",
    "/usr/local/sbin/apiwpp-deployctl verify",
    "/usr/local/sbin/blindou-hostctl verify",
    "/usr/local/sbin/blindou-deployctl status",
    "systemctl reset-failed secondary-slot-metrics.service",
    "verify-secondary-slot-artifacts.py",
    "bootstrap-secondary-slotctl.sh",
    "Export-ModuleMember -Function Invoke-SecondarySlotSudoBootstrap",
):
    if invariant not in sudo_bootstrap:
        fail(f"invariante ausente no bootstrap autenticado: {invariant}")
for forbidden in (
    "Write-Host $password",
    "Write-Output $password",
    "$env:KEY_SERVIDOR",
):
    if forbidden in sudo_bootstrap:
        fail(f"bootstrap autenticado pode expor credencial: {forbidden}")
for invariant in (
    "git.exe",
    "verify-secondary-slot-artifacts.py",
    "Get-FileHash -Algorithm SHA256",
    "IdentitiesOnly=yes",
    "BatchMode=yes",
    "StrictHostKeyChecking=yes",
    "apiwpp-deployctl verify",
    "blindou-deployctl status",
    "blindou-hostctl verify",
    "Invoke-SecondarySlotSudoBootstrap",
    "secondary-slotctl status",
):
    if invariant not in orchestrator:
        fail(f"invariante ausente no orquestrador do bootstrap: {invariant}")
if "Read-Host" in orchestrator or "Invoke-Expression" in orchestrator:
    fail("orquestrador possui entrada ou execução dinâmica proibida")

for source in (controller, library):
    if "shell=True" in source or re.search(r"\b(?:eval|exec)\s*\(", source):
        fail("controlador não pode executar entrada por shell, eval ou exec")
    if re.search(
        r"kubectl[^\n]*(?:-n\s+|namespace\s+)(?:blindou-production|blindou-edge)"
        r"[^\n]*(?:apply|delete|patch|scale|label|annotate)",
        source,
    ):
        fail("controlador contém mutação de recurso Blindou")
    if "apiwpp-deployctl" in source or "saferwpp-deployctl" in source:
        fail("controlador compartilhado não pode invocar controlador de aplicação sob o lock global")

for relative in (
    "operations/remote/secondary_slot.py",
    "operations/remote/secondary-slotctl",
    "operations/remote/test-secondary-slot.py",
):
    source_path = ROOT / relative
    compile(source_path.read_text(encoding="utf-8"), str(source_path), "exec")

test_result = subprocess.run(
    [sys.executable, str(ROOT / "operations/remote/test-secondary-slot.py")],
    cwd=ROOT,
    check=False,
    capture_output=True,
    text=True,
    encoding="utf-8",
    timeout=60,
)
if test_result.returncode != 0:
    fail(f"testes unitários falharam: {test_result.stderr.strip()}")

secret_pattern = re.compile(
    r"BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY|"
    r"(?i:(?:password|token|secret|private[_-]?key)\s*[:=]\s*['\"]?[A-Za-z0-9+_.-][A-Za-z0-9/+_.-]{11,})"
)
secret_scan_roots = (
    ROOT / "platform/secondary-slot",
    ROOT / "operations/remote/secondary-slotctl",
    ROOT / "operations/remote/secondary_slot.py",
    ROOT / "operations/remote/secondary-slotctl.sudoers",
    ROOT / "operations/remote/bootstrap-secondary-slotctl.sh",
    ROOT / "runbooks/secondary-slot.md",
)
for root in secret_scan_roots:
    paths = root.rglob("*") if root.is_dir() else (root,)
    for path in paths:
        if path.is_file() and secret_pattern.search(path.read_text(encoding="utf-8")):
            fail(f"possível segredo encontrado em {path.relative_to(ROOT)}")

print("secondary_slot_artifacts=passed")
