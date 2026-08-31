#!/usr/bin/env python3
"""Extrai e valida uma release DRE assinada em escopo Kubernetes fechado."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile
from typing import Any, Iterable

import yaml


RELEASE_ID_RE = re.compile(r"^dre-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$")
REVISION_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
FCM_PROJECT_RE = re.compile(r"^[a-z][a-z0-9-]{4,29}$")
IMAGE_RE = re.compile(r"^[a-z0-9][a-z0-9._:/-]*@sha256:[0-9a-f]{64}$")
DNS_NAME_RE = re.compile(r"^[a-z0-9](?:[-a-z0-9]*[a-z0-9])?$")

PRODUCTION_STAGE_FILES = (
    "00-platform.yaml",
    "10-migrations.yaml",
    "20-database-access.yaml",
    "30-runtime.yaml",
)
VALIDATION_STAGE_FILES = (
    "40-validation-platform.yaml",
    "41-validation-migrations.yaml",
    "42-validation-database-access.yaml",
    "43-validation-runtime.yaml",
    "44-validation-bootstrap.yaml",
    "45-validation-e2e.yaml",
)
SCHEMA_1_EVIDENCE_FILES = {
    "release.json",
    "supply-chain.json",
    "monitoring/alerts-k3s.yml",
    "sbom/rust.spdx.json",
    "sbom/postgres.spdx.json",
    "scan/rust.json",
    "scan/postgres.json",
}
SCHEMA_2_EVIDENCE_FILES = SCHEMA_1_EVIDENCE_FILES | {
    "sbom/validation.spdx.json",
    "scan/validation.json",
}

ALLOWED_IDENTITIES: dict[str, set[tuple[str, str]]] = {
    "00-platform.yaml": {
        ("Namespace", "dre-production"),
        ("StorageClass", "dre-local-retain"),
        ("ConfigMap", "dre-postgres-config"),
        ("ConfigMap", "dre-runtime-config"),
        ("ConfigMap", "dre-database-access-script"),
        ("ServiceAccount", "dre-postgres"),
        ("ServiceAccount", "dre-api"),
        ("ServiceAccount", "dre-worker"),
        ("ServiceAccount", "dre-migrator"),
        ("ServiceAccount", "dre-database-access"),
        ("ServiceAccount", "dre-admin"),
        ("ResourceQuota", "dre-production-quota"),
        ("LimitRange", "dre-production-defaults"),
        ("Service", "dre-postgres"),
        ("PersistentVolumeClaim", "dre-postgres-data"),
        ("StatefulSet", "dre-postgres"),
        ("PodDisruptionBudget", "dre-postgres"),
        ("NetworkPolicy", "default-deny"),
        ("NetworkPolicy", "allow-cluster-dns"),
        ("NetworkPolicy", "postgres-ingress"),
        ("NetworkPolicy", "application-to-postgres"),
        ("NetworkPolicy", "worker-fcm-egress"),
        ("NetworkPolicy", "postgres-backup-egress"),
        ("NetworkPolicy", "api-ingress"),
        ("NetworkPolicy", "metrics-ingress"),
    },
    "10-migrations.yaml": {("Job", "dre-database-migrate")},
    "20-database-access.yaml": {("Job", "dre-database-access")},
    "30-runtime.yaml": {
        ("Deployment", "dre-api"),
        ("Service", "dre-api"),
        ("PodDisruptionBudget", "dre-api"),
        ("Deployment", "dre-worker"),
        ("Service", "dre-worker-metrics"),
        ("PodDisruptionBudget", "dre-worker"),
    },
    "40-validation-platform.yaml": {
        ("Namespace", "dre-validation"),
        ("ConfigMap", "dre-postgres-config"),
        ("ConfigMap", "dre-runtime-config"),
        ("ConfigMap", "dre-database-access-script"),
        ("ServiceAccount", "dre-postgres"),
        ("ServiceAccount", "dre-api"),
        ("ServiceAccount", "dre-worker"),
        ("ServiceAccount", "dre-migrator"),
        ("ServiceAccount", "dre-database-access"),
        ("ServiceAccount", "dre-admin"),
        ("ResourceQuota", "dre-validation-quota"),
        ("LimitRange", "dre-validation-defaults"),
        ("Service", "dre-postgres"),
        ("PersistentVolumeClaim", "dre-postgres-data"),
        ("StatefulSet", "dre-postgres"),
        ("NetworkPolicy", "default-deny"),
        ("NetworkPolicy", "allow-cluster-dns"),
        ("NetworkPolicy", "postgres-ingress"),
        ("NetworkPolicy", "application-to-postgres"),
        ("NetworkPolicy", "api-ingress"),
        ("NetworkPolicy", "validation-to-api"),
    },
    "41-validation-migrations.yaml": {("Job", "dre-database-migrate")},
    "42-validation-database-access.yaml": {("Job", "dre-database-access")},
    "43-validation-runtime.yaml": {
        ("Deployment", "dre-api"),
        ("Service", "dre-api"),
        ("Deployment", "dre-worker"),
        ("Service", "dre-worker-metrics"),
    },
    "44-validation-bootstrap.yaml": {("Job", "dre-validation-bootstrap")},
    "45-validation-e2e.yaml": {
        ("ServiceAccount", "dre-validation"),
        ("Job", "dre-validation-e2e"),
    },
}
ALLOWED_API_VERSIONS = {
    "v1",
    "apps/v1",
    "batch/v1",
    "networking.k8s.io/v1",
    "policy/v1",
    "storage.k8s.io/v1",
}
ALLOWED_SECRETS = {
    "dre-registry-pull",
    "dre-postgres-admin",
    "dre-database-access",
    "dre-api-runtime",
    "dre-backup-runtime",
    "dre-fcm-runtime",
    "dre-validation-accounts",
}
EXPECTED_ALERTS = {
    "DreK3sApiUnavailable",
    "DreK3sWorkerUnavailable",
    "DreK3sPostgresUnavailable",
    "DreK3sContainerRestartLoop",
    "DreK3sPostgresPvcHigh",
    "DreK3sPostgresPvcCritical",
    "DreK3sPersistentVolumeLost",
    "DreK3sPostgresVolumeMetricsMissing",
}
EXPECTED_REGULAR_CONTAINERS = {
    "StatefulSet/dre-postgres": ("postgres",),
    "Job/dre-database-migrate": ("migrate",),
    "Job/dre-database-access": ("database-access",),
    "Deployment/dre-api": ("api",),
    "Deployment/dre-worker": ("worker",),
    "Job/dre-validation-bootstrap": ("bootstrap",),
    "Job/dre-validation-e2e": ("e2e",),
}
WAIT_FOR_POSTGRES_SCRIPT = "\n".join(
    (
        "attempt=1",
        'while [ "$attempt" -le 12 ]; do',
        "  if /usr/local/bin/pg_isready \\",
        "    --host=dre-postgres \\",
        "    --port=5432 \\",
        "    --username=dre_postgres_admin \\",
        "    --dbname=dre \\",
        "    --timeout=3; then",
        "    exit 0",
        "  fi",
        '  if [ "$attempt" -eq 12 ]; then',
        "    printf 'PostgreSQL não ficou pronto para o bootstrap de acesso\\n' >&2",
        "    exit 1",
        "  fi",
        "  delay=$((1 << (attempt - 1)))",
        '  if [ "$delay" -gt 5 ]; then',
        "    delay=5",
        "  fi",
        '  sleep "$delay"',
        "  attempt=$((attempt + 1))",
        "done",
        "",
    )
)


def fail(message: str) -> None:
    raise SystemExit(f"[dre-release-verify] ERRO: {message}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, description: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{description} inválido: {error}")
    if not isinstance(value, dict):
        fail(f"{description} deve ser um objeto JSON")
    return value


def validate_member(member: tarfile.TarInfo) -> str:
    pure = PurePosixPath(member.name)
    if pure.is_absolute() or not pure.parts or ".." in pure.parts:
        fail(f"caminho inseguro no archive: {member.name}")
    normalized = str(pure)
    if normalized.startswith("./"):
        normalized = normalized[2:]
    if not normalized or normalized == ".":
        fail("entrada vazia no archive")
    if not member.isfile() and not member.isdir():
        fail(f"tipo de entrada proibido no archive: {member.name}")
    if member.isfile() and member.size > 20 * 1024 * 1024:
        fail(f"arquivo excede 20 MiB: {member.name}")
    return normalized.rstrip("/")


def extract_archive(archive: Path, destination: Path) -> list[Path]:
    if destination.exists():
        if destination.is_symlink() or not destination.is_dir():
            fail("diretório de extração inválido")
        if any(destination.iterdir()):
            fail("diretório de extração deve estar vazio")
    else:
        destination.mkdir(mode=0o700, parents=True)

    files: list[Path] = []
    total_size = 0
    with tarfile.open(archive, mode="r:gz") as bundle:
        members = bundle.getmembers()
        if len(members) > 32:
            fail("archive contém entradas demais")
        seen: set[str] = set()
        for member in members:
            normalized = validate_member(member)
            if normalized in seen:
                fail(f"entrada duplicada no archive: {normalized}")
            seen.add(normalized)
            target = destination.joinpath(*PurePosixPath(normalized).parts)
            try:
                target.relative_to(destination)
            except ValueError:
                fail(f"caminho escapou do diretório de extração: {member.name}")
            if member.isdir():
                target.mkdir(mode=0o700, parents=True, exist_ok=True)
                continue
            total_size += member.size
            if total_size > 60 * 1024 * 1024:
                fail("conteúdo descompactado excede 60 MiB")
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            source = bundle.extractfile(member)
            if source is None:
                fail(f"não foi possível ler {member.name}")
            with source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            target.chmod(0o600)
            files.append(target)
    return files


def load_yaml_documents(path: Path) -> list[dict[str, Any]]:
    try:
        loaded = list(yaml.safe_load_all(path.read_text(encoding="utf-8-sig")))
    except (UnicodeDecodeError, yaml.YAMLError) as error:
        fail(f"YAML inválido em {path.name}: {error}")
    documents = [document for document in loaded if document is not None]
    if not documents or not all(isinstance(document, dict) for document in documents):
        fail(f"YAML vazio ou não estruturado em {path.name}")
    return documents


def pod_specs(document: dict[str, Any]) -> Iterable[dict[str, Any]]:
    if document.get("kind") in {"Deployment", "StatefulSet", "Job"}:
        yield document.get("spec", {}).get("template", {}).get("spec", {})


def validate_container(
    container: dict[str, Any], resource: str, expected_images: dict[str, str]
) -> None:
    image = container.get("image")
    if not isinstance(image, str) or not IMAGE_RE.fullmatch(image):
        fail(f"imagem sem digest em {resource}")
    container_name = container.get("name")
    component_by_container = {
        "postgres": "postgres",
        "database-access": "postgres",
        "wait-for-postgres": "postgres",
        "e2e": "validation",
        "api": "rust",
        "worker": "rust",
        "migrate": "rust",
        "bootstrap": "rust",
    }
    component = component_by_container.get(container_name)
    if component is None or expected_images.get(component) != image:
        fail(f"imagem incompatível com o container em {resource}")
    resources = container.get("resources", {})
    for field in ("requests", "limits"):
        values = resources.get(field, {})
        if not isinstance(values, dict) or not all(
            name in values for name in ("cpu", "memory")
        ):
            fail(f"requests/limits incompletos em {resource}")
    security = container.get("securityContext", {})
    if security.get("allowPrivilegeEscalation") is not False:
        fail(f"allowPrivilegeEscalation deve ser false em {resource}")
    if security.get("readOnlyRootFilesystem") is not True:
        fail(f"readOnlyRootFilesystem deve ser true em {resource}")
    if "ALL" not in security.get("capabilities", {}).get("drop", []):
        fail(f"capabilities ALL não removidas em {resource}")
    if security.get("privileged") is True:
        fail(f"container privilegiado em {resource}")
    for port in container.get("ports", []) or []:
        if "hostPort" in port:
            fail(f"hostPort proibido em {resource}")


def validate_wait_for_postgres(container: dict[str, Any], resource: str) -> None:
    if resource != "Job/dre-database-access":
        fail(f"wait-for-postgres fora do Job autorizado em {resource}")
    expected_keys = {
        "name",
        "image",
        "imagePullPolicy",
        "command",
        "args",
        "resources",
        "securityContext",
    }
    if set(container) != expected_keys:
        fail("campos do wait-for-postgres divergem do contrato fechado")
    if container.get("imagePullPolicy") != "IfNotPresent":
        fail("política de imagem do wait-for-postgres diverge")
    if container.get("command") != ["/bin/sh", "-ec"]:
        fail("comando do wait-for-postgres diverge")
    if container.get("args") != [WAIT_FOR_POSTGRES_SCRIPT]:
        fail("script do wait-for-postgres diverge")
    if container.get("resources") != {
        "requests": {"cpu": "10m", "memory": "32Mi"},
        "limits": {"cpu": "100m", "memory": "64Mi"},
    }:
        fail("recursos do wait-for-postgres divergem")
    if container.get("securityContext") != {
        "allowPrivilegeEscalation": False,
        "capabilities": {"drop": ["ALL"]},
        "readOnlyRootFilesystem": True,
    }:
        fail("segurança do wait-for-postgres diverge")


def validate_pod_spec(
    spec: dict[str, Any], resource: str, expected_images: dict[str, str]
) -> None:
    for field in ("hostNetwork", "hostPID", "hostIPC"):
        if spec.get(field) is True:
            fail(f"{field} proibido em {resource}")
    if spec.get("automountServiceAccountToken") is not False:
        fail(f"token de ServiceAccount deve estar desabilitado em {resource}")
    security = spec.get("securityContext", {})
    if security.get("runAsNonRoot") is not True:
        fail(f"runAsNonRoot ausente em {resource}")
    if security.get("seccompProfile", {}).get("type") != "RuntimeDefault":
        fail(f"seccomp RuntimeDefault ausente em {resource}")
    regular_containers = spec.get("containers")
    init_containers = spec.get("initContainers", []) or []
    if not isinstance(regular_containers, list) or not regular_containers:
        fail(f"workload sem container em {resource}")
    if not isinstance(init_containers, list) or not all(
        isinstance(container, dict) for container in init_containers
    ):
        fail(f"initContainers inválidos em {resource}")
    if not all(isinstance(container, dict) for container in regular_containers):
        fail(f"containers inválidos em {resource}")
    expected_regular = EXPECTED_REGULAR_CONTAINERS.get(resource)
    regular_names = tuple(container.get("name") for container in regular_containers)
    if expected_regular is None or regular_names != expected_regular:
        fail(f"containers regulares divergem em {resource}")
    init_names = tuple(container.get("name") for container in init_containers)
    allowed_init_names = (
        {(), ("wait-for-postgres",)}
        if resource == "Job/dre-database-access"
        else {()}
    )
    if init_names not in allowed_init_names:
        fail(f"initContainers divergem em {resource}")
    for container in init_containers + regular_containers:
        validate_container(container, resource, expected_images)
        if container.get("name") == "wait-for-postgres":
            validate_wait_for_postgres(container, resource)
    for volume in spec.get("volumes", []) or []:
        if "hostPath" in volume:
            fail(f"hostPath proibido em {resource}")
        secret = volume.get("secret")
        if secret and secret.get("secretName") not in ALLOWED_SECRETS:
            fail(f"Secret fora da allowlist em {resource}")


def validate_release_metadata(
    root: Path, release_id: str
) -> tuple[dict[str, Any], dict[str, str], int]:
    release = load_json(root / "release.json", "release.json")
    schema = release.get("schema")
    schema_1_keys = {
        "schema",
        "generated_at_utc",
        "target",
        "namespace",
        "rust_image",
        "postgres_image",
        "web_origin",
        "backup_s3_endpoint",
        "backup_s3_bucket",
        "backup_s3_region",
        "backup_repository_path",
        "fcm_enabled",
        "fcm_project_id",
        "stages",
        "stage_sha256",
    }
    schema_2_keys = schema_1_keys | {
        "migration_count",
        "validation_image",
        "validation_namespace",
        "validation_stages",
    }
    expected_release_keys = schema_1_keys if schema == 1 else schema_2_keys
    if schema not in {1, 2} or set(release) != expected_release_keys:
        fail("campos de release.json divergem do contrato fechado")
    if release.get("target") != "local-k3s-x86_64":
        fail("target da release não é o K3s local x86_64")
    if release.get("namespace") != "dre-production":
        fail("namespace da release diverge")
    if release.get("stages") != list(PRODUCTION_STAGE_FILES):
        fail("ordem dos estágios diverge")
    stage_files = PRODUCTION_STAGE_FILES
    if schema == 2:
        if release.get("migration_count") != 9:
            fail("schema 2 deve declarar exatamente nove migrations")
        if release.get("validation_namespace") != "dre-validation":
            fail("namespace de validação diverge")
        if release.get("validation_stages") != list(VALIDATION_STAGE_FILES):
            fail("ordem dos estágios de validação diverge")
        stage_files += VALIDATION_STAGE_FILES
    checksums = release.get("stage_sha256")
    if not isinstance(checksums, dict) or set(checksums) != set(stage_files):
        fail("mapa de checksums dos estágios diverge")
    for stage in stage_files:
        expected = checksums.get(stage)
        if not isinstance(expected, str) or not SHA256_RE.fullmatch(expected):
            fail(f"checksum inválido em {stage}")
        if sha256_file(root / stage) != expected:
            fail(f"checksum do estágio diverge: {stage}")
    image_fields = ["rust_image", "postgres_image"]
    if schema == 2:
        image_fields.append("validation_image")
    release_images: dict[str, str] = {}
    for field in image_fields:
        image = release.get(field)
        if not isinstance(image, str) or not IMAGE_RE.fullmatch(image):
            fail(f"imagem inválida no recibo: {field}")
        release_images[field.removesuffix("_image")] = image
    if len(set(release_images.values())) != len(release_images):
        fail("imagens da release não podem coincidir")
    fcm_enabled = release.get("fcm_enabled")
    fcm_project_id = release.get("fcm_project_id")
    if not isinstance(fcm_enabled, bool) or not isinstance(fcm_project_id, str):
        fail("configuração FCM inválida na release")
    if fcm_enabled and not FCM_PROJECT_RE.fullmatch(fcm_project_id):
        fail("release com FCM exige project ID válido")
    if not fcm_enabled and fcm_project_id:
        fail("release sem FCM deve manter project ID vazio")

    supply = load_json(root / "supply-chain.json", "supply-chain.json")
    if supply.get("schema") != 1 or supply.get("release_id") != release_id:
        fail("identidade da cadeia de fornecimento diverge")
    revision = supply.get("source_revision")
    if not isinstance(revision, str) or not REVISION_RE.fullmatch(revision):
        fail("revisão-fonte inválida")
    if not release_id.endswith(revision[:12]):
        fail("release ID não corresponde à revisão-fonte")
    if supply.get("target") != "local-k3s-x86_64":
        fail("target da cadeia de fornecimento diverge")
    images = supply.get("images")
    if not isinstance(images, dict) or set(images) != set(release_images):
        fail("componentes da cadeia de fornecimento divergem da release")
    for component, expected_image in release_images.items():
        evidence = images.get(component)
        if not isinstance(evidence, dict):
            fail(f"evidência ausente para {component}")
        if evidence.get("reference") != expected_image:
            fail(f"digest de {component} diverge da release")
        if evidence.get("platform") != "linux/amd64":
            fail(f"plataforma de {component} não é linux/amd64")
        for evidence_type in ("sbom", "scan"):
            item = evidence.get(evidence_type)
            if not isinstance(item, dict):
                fail(f"{evidence_type} ausente para {component}")
            expected_path = f"{evidence_type}/{component}." + (
                "spdx.json" if evidence_type == "sbom" else "json"
            )
            if item.get("path") != expected_path:
                fail(f"caminho de {evidence_type} diverge para {component}")
            expected_sha = item.get("sha256")
            if not isinstance(expected_sha, str) or not SHA256_RE.fullmatch(
                expected_sha
            ):
                fail(f"checksum de {evidence_type} inválido para {component}")
            if sha256_file(root / expected_path) != expected_sha:
                fail(f"checksum de {evidence_type} diverge para {component}")
        scan = evidence["scan"]
        if scan.get("status") != "passed":
            fail(f"scan de {component} não foi aprovado")
        if scan.get("critical_vulnerabilities") != 0:
            fail(f"scan de {component} contém vulnerabilidade crítica")
        if scan.get("high_vulnerabilities") != 0:
            fail(f"scan de {component} contém vulnerabilidade alta")
        load_json(root / evidence["sbom"]["path"], f"SBOM {component}")
        load_json(root / evidence["scan"]["path"], f"scan {component}")
    migration_count = 7 if schema == 1 else 9
    return release, release_images, migration_count


def validate_documents(
    root: Path, release: dict[str, Any], expected_images: dict[str, str]
) -> None:
    schema = release["schema"]
    stage_files = PRODUCTION_STAGE_FILES
    if schema == 2:
        stage_files += VALIDATION_STAGE_FILES
    permanent_containers: list[str] = []
    for stage in stage_files:
        expected_identities = ALLOWED_IDENTITIES[stage]
        expected_namespace = (
            "dre-validation" if stage in VALIDATION_STAGE_FILES else "dre-production"
        )
        documents = load_yaml_documents(root / stage)
        actual_identities: set[tuple[str, str]] = set()
        for document in documents:
            api_version = document.get("apiVersion")
            kind = document.get("kind")
            metadata = document.get("metadata", {})
            name = metadata.get("name")
            namespace = metadata.get("namespace")
            if api_version not in ALLOWED_API_VERSIONS:
                fail(f"apiVersion fora da allowlist em {stage}: {api_version}")
            if not isinstance(kind, str) or not isinstance(name, str):
                fail(f"identidade Kubernetes inválida em {stage}")
            if not DNS_NAME_RE.fullmatch(name):
                fail(f"nome Kubernetes inválido em {stage}: {name}")
            identity = (kind, name)
            if identity in actual_identities:
                fail(f"recurso duplicado em {stage}: {kind}/{name}")
            actual_identities.add(identity)
            if kind in {"Namespace", "StorageClass"}:
                if namespace is not None:
                    fail(f"recurso cluster-scoped possui namespace: {kind}/{name}")
            elif namespace != expected_namespace:
                fail(f"recurso fora de {expected_namespace}: {kind}/{name}")
            labels = metadata.get("labels", {})
            if labels.get("app.kubernetes.io/part-of") != "dre-familiar":
                fail(f"ownership DRE ausente em {kind}/{name}")

            if kind == "Secret":
                fail("Secret não pode integrar a release")
            if kind == "Namespace":
                labels = metadata.get("labels", {})
                expected_lifecycle = (
                    "disposable" if name == "dre-validation" else "always-active"
                )
                if labels.get("dre.familiar/lifecycle") != expected_lifecycle:
                    fail("lifecycle do namespace DRE diverge")
                if labels.get("pod-security.kubernetes.io/enforce") != "restricted":
                    fail("Pod Security restricted ausente")
                if labels.get("pod-security.kubernetes.io/enforce-version") != "v1.36":
                    fail("versão de Pod Security diverge")
            if kind == "StorageClass":
                if document.get("reclaimPolicy") != "Retain":
                    fail("StorageClass de produção deve usar Retain")
                if document.get("provisioner") != "rancher.io/local-path":
                    fail("provisionador da StorageClass diverge")
            if kind == "ServiceAccount":
                if document.get("automountServiceAccountToken") is not False:
                    fail(f"ServiceAccount permite token automático: {name}")
            if kind == "Service":
                spec = document.get("spec", {})
                if spec.get("type", "ClusterIP") != "ClusterIP":
                    fail(f"Service público: {name}")
                if spec.get("externalIPs") or spec.get("loadBalancerIP"):
                    fail(f"Service possui endereço externo: {name}")
                for port in spec.get("ports", []) or []:
                    if "nodePort" in port:
                        fail(f"Service possui nodePort: {name}")
            if kind == "PersistentVolumeClaim":
                spec = document.get("spec", {})
                expected_storage_class = (
                    "local-path" if expected_namespace == "dre-validation" else "dre-local-retain"
                )
                if spec.get("storageClassName") != expected_storage_class:
                    fail("PVC não usa a StorageClass aprovada para seu lifecycle")
                storage = spec.get("resources", {}).get("requests", {}).get("storage")
                expected_storage = "5Gi" if expected_namespace == "dre-validation" else "20Gi"
                if storage != expected_storage:
                    fail("PVC PostgreSQL possui capacidade divergente")
            if kind == "Job":
                spec = document.get("spec", {})
                if spec.get("ttlSecondsAfterFinished") != 86400:
                    fail(f"Job sem TTL aprovado: {name}")
                if not isinstance(spec.get("activeDeadlineSeconds"), int):
                    fail(f"Job sem deadline: {name}")
            if kind == "NetworkPolicy" and name == "default-deny":
                if document.get("spec", {}).get("podSelector") != {}:
                    fail("default-deny não seleciona todos os pods")
            for spec in pod_specs(document):
                validate_pod_spec(spec, f"{kind}/{name}", expected_images)
                if (
                    stage in PRODUCTION_STAGE_FILES
                    and kind in {"Deployment", "StatefulSet"}
                ):
                    permanent_containers.extend(
                        container.get("name", "")
                        for container in spec.get("containers", []) or []
                    )
        if actual_identities != expected_identities:
            missing = sorted(expected_identities - actual_identities)
            extra = sorted(actual_identities - expected_identities)
            fail(f"escopo de {stage} diverge; ausentes={missing}, extras={extra}")
    if sorted(permanent_containers) != ["api", "postgres", "worker"]:
        fail("release deve possuir exatamente api, worker e postgres permanentes")


def validate_alerts(root: Path) -> None:
    documents = load_yaml_documents(root / "monitoring/alerts-k3s.yml")
    if len(documents) != 1 or set(documents[0]) != {"groups"}:
        fail("arquivo de alertas possui formato inesperado")
    names: set[str] = set()
    for group in documents[0].get("groups", []):
        if not isinstance(group, dict):
            fail("grupo Prometheus inválido")
        for rule in group.get("rules", []):
            if not isinstance(rule, dict) or not isinstance(rule.get("alert"), str):
                fail("regra Prometheus inválida")
            names.add(rule["alert"])
            expression = rule.get("expr")
            if not isinstance(expression, str) or "dre-production" not in expression:
                fail(f"alerta fora do namespace DRE: {rule.get('alert')}")
    if names != EXPECTED_ALERTS:
        fail("conjunto de alertas K3s diverge")


def main() -> None:
    if len(sys.argv) != 5:
        fail("uso: dre-release-verify.py ARCHIVE DESTINO RELEASE_ID SHA256")
    archive = Path(sys.argv[1]).resolve(strict=True)
    destination = Path(sys.argv[2]).resolve(strict=False)
    release_id = sys.argv[3]
    expected_sha = sys.argv[4]
    if not RELEASE_ID_RE.fullmatch(release_id):
        fail("release ID inválido")
    if not SHA256_RE.fullmatch(expected_sha):
        fail("SHA-256 esperado inválido")
    if archive.is_symlink() or not archive.is_file():
        fail("archive ausente ou simbólico")
    if sha256_file(archive) != expected_sha:
        fail("SHA-256 do archive diverge")

    paths = extract_archive(archive, destination)
    relative = {
        str(path.relative_to(destination)).replace(os.sep, "/") for path in paths
    }
    if "release.json" not in relative:
        fail("release.json ausente no archive")
    release_preview = load_json(destination / "release.json", "release.json")
    schema = release_preview.get("schema")
    if schema == 1:
        required_files = set(PRODUCTION_STAGE_FILES) | SCHEMA_1_EVIDENCE_FILES
    elif schema == 2:
        required_files = (
            set(PRODUCTION_STAGE_FILES)
            | set(VALIDATION_STAGE_FILES)
            | SCHEMA_2_EVIDENCE_FILES
        )
    else:
        fail("schema de release incompatível")
    if relative != required_files:
        missing = sorted(required_files - relative)
        extra = sorted(relative - required_files)
        fail(f"conteúdo do archive diverge; ausentes={missing}, extras={extra}")
    release, expected_images, migration_count = validate_release_metadata(
        destination, release_id
    )
    validate_documents(destination, release, expected_images)
    validate_alerts(destination)
    print(
        "dre_release_bundle=passed "
        f"schema={schema} migrations={migration_count} "
        "namespace=dre-production permanent_containers=3"
    )


if __name__ == "__main__":
    main()
