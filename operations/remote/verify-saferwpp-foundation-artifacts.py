#!/usr/bin/env python3
"""Valida offline os artefatos declarativos da fundação SaferWPP."""

from __future__ import annotations

import json
import pathlib
import re

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]
FOUNDATION_ROOT = ROOT / "platform" / "saferwpp"


def fail(message: str) -> None:
    raise SystemExit(f"[verify-saferwpp-foundation-artifacts] ERRO: {message}")


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file() or path.is_symlink():
        fail(f"arquivo ausente ou simbólico: {relative}")
    return path.read_text(encoding="utf-8")


def yaml_documents(relative: str) -> list[dict]:
    documents = [doc for doc in yaml.safe_load_all(read(relative)) if doc]
    if not documents or not all(isinstance(doc, dict) for doc in documents):
        fail(f"YAML vazio ou inválido: {relative}")
    return documents


def require_equal(actual: object, expected: object, description: str) -> None:
    if actual != expected:
        fail(f"{description}: esperado {expected!r}, obtido {actual!r}")


def by_kind_name(documents: list[dict], kind: str, name: str) -> dict:
    for document in documents:
        metadata = document.get("metadata", {})
        if document.get("kind") == kind and metadata.get("name") == name:
            return document
    fail(f"{kind}/{name} ausente")


foundation_docs = yaml_documents("platform/saferwpp/foundation.yaml")
require_equal(len(foundation_docs), 1, "quantidade de contratos de fundação")
foundation = foundation_docs[0]
require_equal(foundation.get("kind"), "SaferWppLabFoundation", "kind da fundação")
spec = foundation["spec"]
lifecycle = spec["lifecycle"]
require_equal(lifecycle["secondarySlotContract"], "platform.servidor.local/v1", "contrato do slot")
require_equal(
    lifecycle["secondarySlotStateFile"],
    "/var/lib/servidor-local/secondary-slot/state",
    "atestado do slot",
)
require_equal(lifecycle["secondarySlotReservationRequired"], True, "reserva do slot")

postgres = spec["postgres"]
require_equal(postgres["version"], 18, "versão PostgreSQL")
require_equal(postgres["logicalClusterId"], "saferwpp-lab", "ID lógico PostgreSQL")
require_equal(postgres["operationalClusterName"], "saferwpp_lab", "nome operacional PostgreSQL")
require_equal(postgres["systemdUnit"], "postgresql@18-saferwpp_lab.service", "unit PostgreSQL")
require_equal(postgres["endpoint"]["port"], 55432, "porta PostgreSQL")
require_equal(postgres["connections"]["physicalCeiling"], 24, "teto físico de conexões")
require_equal(postgres["connections"]["ordinaryBudget"], 19, "orçamento ordinário")
allocations = postgres["connections"]["allocations"]
require_equal(sum(allocations.values()), 19, "soma das alocações ordinárias")
require_equal(allocations["pgbouncerRuntime"], 10, "backends PgBouncer")
require_equal(postgres["resources"]["cpuQuotaPercent"], 100, "teto de CPU")
require_equal(postgres["resources"]["memoryHighMi"], 1536, "MemoryHigh")
require_equal(postgres["resources"]["memoryMaxMi"], 2048, "MemoryMax")

backup = spec["backup"]
require_equal(backup["contractVersion"], "saferwpp.backup-preflight/v2", "contrato de backup")
require_equal(backup["stanza"], "saferwpp-lab", "stanza pgBackRest")
require_equal(set(backup["repositories"]), {"local", "r2"}, "repositórios de backup")
require_equal(backup["repositories"]["r2"]["bucket"], "saferwpp-postgres-backup-lab", "bucket R2")
require_equal(
    set(backup["repositories"]["r2"]["requiredEnvironment"]),
    {
        "PGBACKREST_REPO2_S3_ENDPOINT",
        "PGBACKREST_REPO2_S3_KEY",
        "PGBACKREST_REPO2_S3_KEY_SECRET",
        "PGBACKREST_REPO2_CIPHER_PASS",
    },
    "variáveis protegidas do repo2",
)
require_equal(backup["localEncryptionEnvironment"], "PGBACKREST_REPO1_CIPHER_PASS", "cifra do repo1")
require_equal(backup["walArchivingRequired"], True, "WAL obrigatório")
require_equal(backup["baselineRestoreEvidenceRequired"], True, "restore-base obrigatório")
require_equal(backup["postMigrationRestoreRequired"], True, "restore pós-migration obrigatório")
require_equal(
    backup["postMigrationRestoreVerifications"],
    {
        "rolesVerified": True,
        "grantsVerified": True,
        "rlsVerified": True,
    },
    "verificações do restore pós-migration",
)

monitoring = spec["monitoring"]["exporter"]
require_equal(monitoring["identity"], "saferwpp-postgres-exporter", "identidade do exporter")
require_equal(monitoring["listenAddress"], "127.0.0.1", "listener do exporter")
require_equal(monitoring["listenPort"], 9188, "porta do exporter")
require_equal(monitoring["connectionAllocation"], 1, "conexão do exporter")

base_documents = yaml_documents("platform/base/project-spaces.yaml")
base_namespaces = yaml_documents("platform/base/namespaces.yaml")
saferwpp_namespace = by_kind_name(base_namespaces, "Namespace", "saferwpp-lab")
require_equal(
    saferwpp_namespace["metadata"]["labels"]["platform.servidor.local/secondary-slot-member"],
    "saferwpp",
    "membership do slot em saferwpp-lab",
)
if "platform.servidor.local/secondary-slot-state" in saferwpp_namespace["metadata"]["labels"]:
    fail("manifesto estático não pode controlar o gate dinâmico de saferwpp-lab")
application_quotas = [
    doc
    for doc in base_documents
    if doc.get("kind") == "ResourceQuota"
    and doc.get("metadata", {}).get("namespace") == "saferwpp-lab"
]
require_equal(len(application_quotas), 1, "quota do saferwpp-lab")
application_hard = application_quotas[0]["spec"]["hard"]
require_equal(application_hard["requests.cpu"], "2", "requests.cpu do saferwpp-lab")
require_equal(application_hard["requests.memory"], "4Gi", "requests.memory do saferwpp-lab")
require_equal(application_hard["limits.cpu"], "7", "limits.cpu do saferwpp-lab")
require_equal(application_hard["limits.memory"], "8Gi", "limits.memory do saferwpp-lab")
require_equal(application_hard["persistentvolumeclaims"], "3", "PVCs do saferwpp-lab")
require_equal(application_hard["requests.storage"], "24Gi", "storage do saferwpp-lab")
require_equal(application_hard["pods"], "12", "pods do saferwpp-lab")

namespace_documents = yaml_documents("platform/saferwpp/00-platform-namespaces.yaml")
budget_documents = yaml_documents("platform/saferwpp/10-platform-budgets.yaml")
for namespace, quota_name, expected in (
    (
        "saferdock-identity",
        "keycloak-exclusive-budget",
        {"requests.cpu": "500m", "requests.memory": "1Gi", "limits.cpu": "1500m", "limits.memory": "2Gi"},
    ),
    (
        "saferdock-platform",
        "control-plane-exclusive-budget",
        {"requests.cpu": "250m", "requests.memory": "512Mi", "limits.cpu": "1", "limits.memory": "1Gi"},
    ),
):
    namespace_doc = by_kind_name(namespace_documents, "Namespace", namespace)
    labels = namespace_doc["metadata"]["labels"]
    require_equal(
        labels["platform.servidor.local/secondary-slot-member"],
        "saferwpp",
        f"membership do slot em {namespace}",
    )
    if "platform.servidor.local/secondary-slot-state" in labels:
        fail(f"manifesto estático não pode controlar o gate dinâmico de {namespace}")
    require_equal(labels["pod-security.kubernetes.io/enforce"], "restricted", f"Pod Security de {namespace}")
    require_equal(labels["pod-security.kubernetes.io/enforce-version"], "v1.36", f"versão Pod Security de {namespace}")
    quota = by_kind_name(budget_documents, "ResourceQuota", quota_name)
    require_equal(quota["metadata"]["namespace"], namespace, f"namespace da quota {quota_name}")
    hard = quota["spec"]["hard"]
    for key, value in expected.items():
        require_equal(hard[key], value, f"{quota_name}.{key}")
    require_equal(hard["persistentvolumeclaims"], "0", f"PVC bloqueado em {namespace}")
    service_accounts = [
        doc
        for doc in budget_documents
        if doc.get("kind") == "ServiceAccount"
        and doc.get("metadata", {}).get("namespace") == namespace
    ]
    require_equal(len(service_accounts), 1, f"ServiceAccount padrão em {namespace}")
    require_equal(service_accounts[0].get("automountServiceAccountToken"), False, f"token automático em {namespace}")
    policies = [
        doc
        for doc in budget_documents
        if doc.get("kind") == "NetworkPolicy"
        and doc.get("metadata", {}).get("namespace") == namespace
    ]
    require_equal(len(policies), 2, f"NetworkPolicies em {namespace}")

if any(doc.get("kind") == "Secret" for doc in namespace_documents + budget_documents):
    fail("a fundação Kubernetes não pode conter Secret")

postgresql_conf = read("platform/saferwpp/postgresql/90-saferwpp-lab.conf")
for invariant in (
    "port = 55432",
    "max_connections = 24",
    "superuser_reserved_connections = 3",
    "reserved_connections = 2",
    "shared_buffers = '512MB'",
    "shared_preload_libraries = 'pg_stat_statements'",
    "track_io_timing = on",
    "archive_timeout = '900s'",
    "--config=/etc/pgbackrest/saferwpp-lab.conf",
    "--stanza=saferwpp-lab",
):
    if invariant not in postgresql_conf:
        fail(f"invariante ausente no postgresql.conf: {invariant}")

hba = read("platform/saferwpp/postgresql/pg_hba.conf")
if hba.count("10.42.0.0/16") != 6:
    fail("HBA não contém exatamente seis identidades SaferWPP vindas do CIDR K3s")
if hba.count("clientcert=verify-full") != 7:
    fail("todas as identidades remotas devem exigir certificado verify-full")
if "0.0.0.0/0       reject" not in hba or "::/0            reject" not in hba:
    fail("HBA não termina com negação explícita IPv4/IPv6")

pgbackrest = read("platform/saferwpp/postgresql/pgbackrest.conf")
for invariant in (
    "repo1-path=/var/lib/pgbackrest/saferwpp-lab",
    "repo2-type=s3",
    "repo2-s3-bucket=saferwpp-postgres-backup-lab",
    "repo2-path=/saferwpp-lab",
    "[saferwpp-lab]",
    "pg1-path=/var/lib/postgresql/18/saferwpp_lab",
    "pg1-port=55432",
):
    if invariant not in pgbackrest:
        fail(f"invariante ausente no pgBackRest: {invariant}")

slice_unit = read("platform/saferwpp/postgresql/saferwpp-postgresql.slice")
for invariant in ("CPUQuota=100%", "MemoryHigh=1536M", "MemoryMax=2048M"):
    if invariant not in slice_unit:
        fail(f"limite systemd ausente: {invariant}")

exporter_unit = read("platform/saferwpp/postgresql/saferwpp-postgres-exporter.service")
for invariant in (
    "User=saferwpp-postgres-exporter",
    "127.0.0.1:9188",
    "postgresql@18-saferwpp_lab.service",
    "NoNewPrivileges=true",
):
    if invariant not in exporter_unit:
        fail(f"invariante ausente no exporter: {invariant}")

kustomization = yaml_documents("platform/saferwpp/kustomization.yaml")[0]
require_equal(
    kustomization["resources"],
    ["00-platform-namespaces.yaml", "10-platform-budgets.yaml"],
    "recursos do kustomization SaferWPP",
)

for timer_name, expected_unit in (
    ("saferwpp-pgbackrest-incr.timer", "saferwpp-pgbackrest-backup@incr.service"),
    ("saferwpp-pgbackrest-diff.timer", "saferwpp-pgbackrest-backup@diff.service"),
    ("saferwpp-pgbackrest-full.timer", "saferwpp-pgbackrest-backup@full.service"),
):
    timer = read(f"platform/saferwpp/postgresql/{timer_name}")
    if f"Unit={expected_unit}" not in timer or "Persistent=true" not in timer:
        fail(f"timer de backup incompleto: {timer_name}")

scrape = yaml.safe_load(read("platform/saferwpp/monitoring/prometheus-scrape.yaml"))
if not isinstance(scrape, list):
    fail("configuração de scrape Prometheus não é uma lista")
require_equal(len(scrape), 1, "quantidade de jobs Prometheus")
require_equal(scrape[0]["job_name"], "saferwpp-postgres", "job Prometheus")
require_equal(scrape[0]["static_configs"][0]["targets"], ["127.0.0.1:9188"], "target Prometheus")
alerts = yaml_documents("platform/saferwpp/monitoring/prometheus-alerts.yaml")
alert_names = {
    rule["alert"]
    for group in alerts[0]["groups"]
    for rule in group["rules"]
}
require_equal(
    alert_names,
    {
        "SaferWppPostgresExporterDown",
        "SaferWppPostgresClusterUnavailable",
        "SaferWppPostgresConnectionBudgetHigh",
        "SaferWppPostgresBackupRepositoryUnhealthy",
        "SaferWppPostgresBackupStale",
        "SaferWppBackupPreflightInvalid",
    },
    "regras de alerta SaferWPP",
)

backup_script = read("operations/remote/saferwpp-pgbackrest-backup")
if "for repository in 1 2" not in backup_script or "incr|diff|full" not in backup_script:
    fail("executor de backup não fecha os dois repositórios e os três tipos")
metrics_script = read("operations/remote/saferwpp-postgres-metrics")
for metric in (
    "saferwpp_postgres_foundation_state",
    "saferwpp_postgres_backup_repository_healthy",
    "saferwpp_postgres_backup_last_success_timestamp_seconds",
    "saferwpp_postgres_backup_preflight_valid",
):
    if metric not in metrics_script:
        fail(f"métrica obrigatória ausente: {metric}")

schema = json.loads(read("platform/saferwpp/backup-preflight.schema.json"))
require_equal(schema["properties"]["contractVersion"]["const"], "saferwpp.backup-preflight/v2", "schema de backup")
require_equal(schema["properties"]["port"]["const"], 55432, "porta no schema de backup")
post_migration_schema = schema["$defs"]["postMigrationRestoreEvidence"]
required_post_migration_verifications = {
    "rolesVerified",
    "grantsVerified",
    "rlsVerified",
}
if not required_post_migration_verifications.issubset(set(post_migration_schema["required"])):
    fail("schema não exige todas as verificações do restore pós-migration")
require_equal(post_migration_schema["additionalProperties"], False, "campos extras no restore pós-migration")
for verification in required_post_migration_verifications:
    require_equal(
        post_migration_schema["properties"][verification],
        {"const": True},
        f"schema de {verification}",
    )
phase_contract = schema["allOf"][0]
require_equal(
    phase_contract["then"]["properties"]["postMigrationRestore"],
    {"$ref": "#/$defs/postMigrationRestoreEvidence"},
    "restore obrigatório na fase rollout",
)
require_equal(
    phase_contract["else"]["properties"]["postMigrationRestore"],
    {"type": "null"},
    "restore pós-migration nulo na fase foundation",
)

metrics_contract = read("operations/remote/saferwpp-postgres-metrics")
for invariant in (
    '.postMigrationRestore == null',
    '.postMigrationRestore.rolesVerified == true',
    '.postMigrationRestore.grantsVerified == true',
    '.postMigrationRestore.rlsVerified == true',
):
    if invariant not in metrics_contract:
        fail(f"validação de evidência ausente nas métricas: {invariant}")

artifact_files = [path for path in FOUNDATION_ROOT.rglob("*") if path.is_file()]
artifact_files.extend(
    [
        ROOT / "operations" / "remote" / "saferwpp-pgbackrest-backup",
        ROOT / "operations" / "remote" / "saferwpp-postgres-metrics",
    ]
)
secret_pattern = re.compile(
    r"BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY|"
    r"(?i:(?:password|token|secret|private[_-]?key)\s*[:=]\s*['\"]?[A-Za-z0-9+_.-][A-Za-z0-9/+_.-]{11,})"
)
for path in artifact_files:
    if secret_pattern.search(path.read_text(encoding="utf-8")):
        fail(f"possível segredo encontrado em {path.relative_to(ROOT)}")

print("saferwpp_foundation_artifacts=passed")
