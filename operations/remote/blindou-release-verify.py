#!/usr/bin/env python3
"""Extrai e valida um bundle assinado do Blindou em escopo Kubernetes fechado."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile
from typing import Any, Iterable

import yaml


RELEASE_RE = re.compile(r"^[0-9a-f]{40}$")
IMAGE_RE = re.compile(r"^[^\s@]+@sha256:[0-9a-f]{64}$")
NAME_RE = re.compile(r"^blindou-[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
WORKER_RE = re.compile(r"^blindou-worker-[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
EXPECTED_WORKER_COUNT = 16
ALLOWED_NETWORK_POLICIES = {
    "default-deny",
    "allow-dns",
    "allow-postgres-from-runtimes",
    "allow-app-internal-dependencies",
    "allow-provider-https-egress",
    "allow-nats-from-core",
    "allow-redis-from-core",
    "allow-ml-from-backend",
    "allow-cloudflared-to-origin",
    "allow-cloudflared-edge",
    "allow-edge-to-backend",
    "allow-edge-to-redirector",
}
NAMESPACES = {"blindou-production", "blindou-edge"}
ALLOWED_KINDS = {
    "ConfigMap",
    "Deployment",
    "Job",
    "LimitRange",
    "NetworkPolicy",
    "PersistentVolumeClaim",
    "ResourceQuota",
    "Service",
    "ServiceAccount",
    "StatefulSet",
}
REQUIRED_FILES = {
    "00-platform.yaml",
    "10-services.yaml",
    "20-nats-config.yaml",
    "30-network-policies.yaml",
    "40-workloads.yaml",
    "60-cloudflared.yaml",
}
ALLOWED_SECRET_NAMES = {
    "blindou-cloudflare-tunnel",
    "blindou-core-secrets",
    "blindou-migration-secrets",
    "blindou-ml-secrets",
    "blindou-nats-auth",
    "blindou-nats-tls",
    "blindou-postgres-client",
    "blindou-redirect-secrets",
    "blindou-redis-auth",
}
GHCR_PULL_SECRET = "blindou-ghcr-pull"


def fail(message: str) -> None:
    raise SystemExit(f"[blindou-release-verify] ERRO: {message}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


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
    if member.isfile() and member.size > 2 * 1024 * 1024:
        fail(f"arquivo excede 2 MiB: {member.name}")
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
        if len(members) > 96:
            fail("archive contém entradas demais")
        for member in members:
            normalized = validate_member(member)
            target = destination.joinpath(*PurePosixPath(normalized).parts)
            try:
                target.relative_to(destination)
            except ValueError:
                fail(f"caminho escapou do diretório de extração: {member.name}")
            if member.isdir():
                target.mkdir(mode=0o700, parents=True, exist_ok=True)
                continue
            total_size += member.size
            if total_size > 20 * 1024 * 1024:
                fail("conteúdo descompactado excede 20 MiB")
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            source = bundle.extractfile(member)
            if source is None:
                fail(f"não foi possível ler {member.name}")
            with source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            target.chmod(0o600)
            files.append(target)
    return files


def pod_specs(document: dict[str, Any]) -> Iterable[dict[str, Any]]:
    kind = document.get("kind")
    spec = document.get("spec", {})
    if kind in {"Deployment", "StatefulSet"}:
        yield spec.get("template", {}).get("spec", {})
    elif kind == "Job":
        yield spec.get("template", {}).get("spec", {})


def validate_container(container: dict[str, Any], resource: str) -> None:
    image = container.get("image", "")
    if not isinstance(image, str) or not IMAGE_RE.fullmatch(image):
        fail(f"imagem sem digest em {resource}")
    resources = container.get("resources", {})
    for field in ("requests", "limits"):
        values = resources.get(field, {})
        if not all(key in values for key in ("cpu", "memory")):
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


def validate_pod_spec(spec: dict[str, Any], resource: str) -> None:
    for field in ("hostNetwork", "hostPID", "hostIPC"):
        if spec.get(field) is True:
            fail(f"{field} proibido em {resource}")
    if spec.get("automountServiceAccountToken") is not False:
        fail(f"token de ServiceAccount deve estar desabilitado em {resource}")
    for container in (spec.get("initContainers", []) or []) + (
        spec.get("containers", []) or []
    ):
        validate_container(container, resource)
    for volume in spec.get("volumes", []) or []:
        if "hostPath" in volume:
            fail(f"hostPath proibido em {resource}")
        secret = volume.get("secret")
        if secret and secret.get("secretName") not in ALLOWED_SECRET_NAMES:
            fail(f"Secret fora da allowlist em {resource}")


def load_documents(paths: Iterable[Path]) -> list[dict[str, Any]]:
    documents: list[dict[str, Any]] = []
    for path in sorted(paths):
        if path.suffix not in {".yaml", ".yml"}:
            fail(f"arquivo fora do contrato: {path.name}")
        try:
            loaded = list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
        except (UnicodeDecodeError, yaml.YAMLError) as error:
            fail(f"YAML inválido em {path.name}: {error}")
        for document in loaded:
            if document is None:
                continue
            if not isinstance(document, dict):
                fail(f"documento YAML não é objeto em {path.name}")
            documents.append(document)
    return documents


def validate_documents(documents: list[dict[str, Any]], release_id: str) -> None:
    deployment_names: set[str] = set()
    worker_names: set[str] = set()
    cloudflared_deployments = 0
    migration_jobs = 0

    for document in documents:
        api_version = document.get("apiVersion")
        kind = document.get("kind")
        metadata = document.get("metadata", {})
        name = metadata.get("name", "")
        namespace = metadata.get("namespace")
        resource = f"{kind}/{namespace}/{name}"

        if kind not in ALLOWED_KINDS:
            fail(f"kind fora da allowlist: {kind}")
        if namespace not in NAMESPACES:
            fail(f"namespace fora do escopo em {resource}")
        name_is_allowed = (
            isinstance(name, str)
            and (
                NAME_RE.fullmatch(name) is not None
                or (kind == "NetworkPolicy" and name in ALLOWED_NETWORK_POLICIES)
            )
        )
        if not name_is_allowed:
            fail(f"nome fora do prefixo Blindou em {resource}")
        if api_version not in {
            "v1",
            "apps/v1",
            "batch/v1",
            "networking.k8s.io/v1",
        }:
            fail(f"apiVersion fora da allowlist em {resource}")

        if kind == "ServiceAccount":
            pull_secrets = document.get("imagePullSecrets", []) or []
            if name == "blindou-runtime":
                if namespace != "blindou-production":
                    fail("ServiceAccount blindou-runtime fora de blindou-production")
                if document.get("automountServiceAccountToken") is not False:
                    fail("ServiceAccount blindou-runtime permite token Kubernetes")
                if pull_secrets != [{"name": GHCR_PULL_SECRET}]:
                    fail("ServiceAccount blindou-runtime não usa exclusivamente o pull secret GHCR")
            elif pull_secrets:
                fail(f"imagePullSecrets inesperado em {resource}")

        if kind == "Service":
            spec = document.get("spec", {})
            if spec.get("type", "ClusterIP") != "ClusterIP":
                fail(f"Service público em {resource}")
            if spec.get("externalIPs"):
                fail(f"externalIPs proibido em {resource}")

        if kind == "Deployment":
            deployment_names.add(name)
            if WORKER_RE.fullmatch(name):
                worker_names.add(name)
            if name == "blindou-cloudflared":
                cloudflared_deployments += 1
                if namespace != "blindou-edge":
                    fail("cloudflared deve permanecer em blindou-edge")
            elif namespace != "blindou-production":
                fail(f"workload de aplicação fora de blindou-production: {name}")

        if kind in {"Job", "StatefulSet"} and namespace != "blindou-production":
            fail(f"{kind} fora de blindou-production: {name}")
        if kind == "Job":
            migration_jobs += 1
            if not name.startswith(f"blindou-migrate-{release_id[:12]}"):
                fail("Job de migration não corresponde à release")

        for spec in pod_specs(document):
            validate_pod_spec(spec, resource)
            template_metadata = document.get("spec", {}).get("template", {}).get(
                "metadata", {}
            )
            labels = template_metadata.get("labels", {})
            annotations = template_metadata.get("annotations", {})
            declared_releases = {
                value
                for value in (
                    labels.get("blindou.io/release"),
                    annotations.get("blindou.io/release"),
                )
                if value is not None
            }
            if declared_releases != {release_id}:
                fail(f"release ausente ou divergente em {resource}")
            if (name == "blindou-backend" or WORKER_RE.fullmatch(name)) and annotations.get(
                "blindou.io/pagarme-first-compatible"
            ) != "true":
                fail(f"compatibilidade Pagar.me-first ausente em {resource}")
            if (name == "blindou-backend" or WORKER_RE.fullmatch(name)) and annotations.get(
                "blindou.io/marketplaces-compatible"
            ) != "true":
                fail(f"compatibilidade com Marketplaces ausente em {resource}")

    required_deployments = {
        "blindou-backend",
        "blindou-ml-affiliate-connector",
        "blindou-redirector",
        "blindou-cloudflared",
    }
    if not required_deployments.issubset(deployment_names):
        fail("deployments centrais ausentes")
    if len(worker_names) != EXPECTED_WORKER_COUNT:
        fail(
            f"eram esperados {EXPECTED_WORKER_COUNT} deployments de workers"
        )
    if cloudflared_deployments != 1:
        fail("deve existir exatamente um Deployment cloudflared")
    if migration_jobs != 1:
        fail("deve existir exatamente um Job de migration")


def main() -> None:
    if len(sys.argv) != 5:
        fail("uso: blindou-release-verify.py ARCHIVE DESTINO RELEASE_ID SHA256")
    archive = Path(sys.argv[1]).resolve(strict=True)
    destination = Path(sys.argv[2]).resolve(strict=False)
    release_id = sys.argv[3]
    expected_sha = sys.argv[4]
    if not RELEASE_RE.fullmatch(release_id):
        fail("release_id inválido")
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha):
        fail("SHA-256 esperado inválido")
    if archive.is_symlink() or not archive.is_file():
        fail("archive ausente ou simbólico")
    if sha256_file(archive) != expected_sha:
        fail("SHA-256 do archive diverge do manifesto assinado")

    paths = extract_archive(archive, destination)
    relative = {str(path.relative_to(destination)).replace(os.sep, "/") for path in paths}
    if not REQUIRED_FILES.issubset(relative):
        fail("archive não contém todos os manifests obrigatórios")
    worker_files = {path for path in relative if path.startswith("workers/")}
    if len(worker_files) != EXPECTED_WORKER_COUNT:
        fail(
            "archive deve conter exatamente "
            f"{EXPECTED_WORKER_COUNT} manifests em workers/"
        )
    allowed = REQUIRED_FILES | worker_files
    if relative != allowed:
        fail("archive contém arquivo fora do contrato")

    documents = load_documents(paths)
    validate_documents(documents, release_id)
    print("[blindou-release-verify] bundle assinado em escopo fechado: passed")


if __name__ == "__main__":
    main()
