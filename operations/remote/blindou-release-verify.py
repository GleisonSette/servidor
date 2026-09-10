#!/usr/bin/env python3
"""Extrai e valida um bundle assinado do Blindou em escopo Kubernetes fechado."""

from __future__ import annotations

import copy
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


RELEASE_RE = re.compile(r"^[0-9a-f]{40}$")
IMAGE_RE = re.compile(r"^[^\s@]+@sha256:[0-9a-f]{64}$")
NAME_RE = re.compile(r"^blindou-[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
WORKER_RE = re.compile(r"^blindou-worker-[a-z0-9]([-a-z0-9]*[a-z0-9])?$")
EXPECTED_WORKER_COUNT = 16
EXPECTED_DEBEZIUM_IMAGE = (
    "ghcr.io/gleisonsette/blindou-debezium@"
    "sha256:04da6c9bfe2276985d8c30e5444b395a63467111225750c06d15d908c8595e08"
)
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
    "blindou-debezium-v3-egress",
    "blindou-dispatch-authority-v3",
    "blindou-dispatch-sender-v3",
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
    "70-dispatch-v3-foundation.yaml",
    "71-dispatch-v3-workloads.yaml",
    "72-dispatch-v3-network-policies.yaml",
    "dispatch-v3/streams.json",
    "dispatch-v3/consumers.json",
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
    "blindou-debezium-v3",
    "blindou-dispatch-authority-v3",
    "blindou-dispatch-authority-v3-database",
    "blindou-dispatch-authority-v3-mtls",
    "blindou-dispatch-authority-v3-nats",
    "blindou-dispatch-authority-v3-provider",
    "blindou-dispatch-sender-v3",
    "blindou-dispatch-sender-v3-mtls",
    "blindou-dispatch-sender-v3-nats",
    "blindou-dispatch-sender-v3-r2",
}
GHCR_PULL_SECRET = "blindou-ghcr-pull"

# D085 do Blindou: esta allowlist descreve somente a transição do heartbeat.
# O restante da configuração, inclusive TLS, offsets e PubAck, deve ser idêntico.
HEARTBEAT_PROPERTIES = {
    "debezium.source.table.include.list": "public.dispatch_outbox_v3,blindou_cdc_state.dispatch_v3_heartbeat",
    "debezium.source.heartbeat.interval.ms": "60000",
    "debezium.source.heartbeat.action.query": "SELECT blindou_cdc_state.pulse_dispatch_v3_heartbeat()",
    "debezium.source.lsn.flush.mode": "connector",
    "debezium.source.database.query.timeout.ms": "5000",
    "debezium.transforms": "ackCdcHeartbeat,outbox,dropNullScheduleHeaders",
    "debezium.transforms.ackCdcHeartbeat.type": "io.blindou.dispatch.v3.AcknowledgeCdcHeartbeat",
    "debezium.predicates": "isCdcHeartbeat",
    "debezium.predicates.isCdcHeartbeat.type": "org.apache.kafka.connect.transforms.predicates.TopicNameMatches",
    "debezium.predicates.isCdcHeartbeat.pattern": "^(__debezium-heartbeat[.]blindou_dispatch_v3|blindou_dispatch_v3[.]blindou_cdc_state[.]dispatch_v3_heartbeat)$",
    "debezium.transforms.outbox.predicate": "isCdcHeartbeat",
    "debezium.transforms.outbox.negate": "true",
    "debezium.transforms.dropNullScheduleHeaders.predicate": "isCdcHeartbeat",
    "debezium.transforms.dropNullScheduleHeaders.negate": "true",
}


def fail(message: str) -> None:
    raise SystemExit(f"[blindou-release-verify] ERRO: {message}")


def heartbeat_properties(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or key in result or key != key.strip():
            fail("propriedades CDC ausentes, duplicadas ou ambíguas")
        result[key] = value
    return result


def validate_heartbeat_config(previous: str, candidate: str) -> None:
    old = heartbeat_properties(previous)
    new = heartbeat_properties(candidate)
    baseline = {
        "debezium.source.table.include.list": "public.dispatch_outbox_v3",
        "debezium.source.heartbeat.interval.ms": "0",
        "debezium.transforms": "outbox,dropNullScheduleHeaders",
    }
    if any(old.get(key) != value for key, value in baseline.items()):
        fail("baseline CDC não corresponde à transição D085")
    if any(key in old for key in HEARTBEAT_PROPERTIES.keys() - baseline.keys()):
        fail("baseline CDC já contém parte da D085")
    if new != {**old, **HEARTBEAT_PROPERTIES}:
        fail("configuração CDC altera contrato fora da D085")


def normalize_heartbeat_release(document: dict[str, Any], release_id: str,
                                backend_image: str, debezium_image: str) -> dict[str, Any]:
    """Normaliza apenas identidades de release/imagem; não normaliza segurança."""
    result = copy.deepcopy(document)
    kind = result.get("kind")
    name = result.get("metadata", {}).get("name")
    if kind == "Job":
        if name != f"blindou-migrate-{release_id[:12]}":
            fail("Job fora da migration assinada")
        result["metadata"]["name"] = "blindou-migrate-RELEASE"
    if kind in {"Deployment", "StatefulSet", "Job"}:
        template = result["spec"]["template"]
        for field in ("labels", "annotations"):
            metadata = template["metadata"].get(field, {})
            if "blindou.io/release" in metadata:
                if metadata["blindou.io/release"] != release_id:
                    fail("anotação não corresponde à release")
                metadata["blindou.io/release"] = "RELEASE"
        for container in template["spec"]["containers"]:
            image = container.get("image")
            if image == backend_image:
                container["image"] = "BACKEND"
            elif image == debezium_image:
                if (kind, name) != ("StatefulSet", "blindou-debezium-v3"):
                    fail("imagem CDC fora do workload exclusivo")
                container["image"] = "DEBEZIUM"
            for variable in container.get("env", []):
                if variable.get("name") == "APP_RELEASE_ID":
                    if variable.get("value") != release_id:
                        fail("APP_RELEASE_ID não corresponde à release")
                    variable["value"] = "RELEASE"
    return result


def validate_heartbeat_transition(previous: list[dict[str, Any]],
                                  candidate: list[dict[str, Any]],
                                  previous_release: str, candidate_release: str,
                                  previous_backend: str, candidate_backend: str,
                                  previous_debezium: str, candidate_debezium: str) -> None:
    """Comparação adicional dos dois bundles já assinados, sem escrita ou K3s."""
    if (not RELEASE_RE.fullmatch(previous_release)
            or not RELEASE_RE.fullmatch(candidate_release)
            or previous_release == candidate_release):
        fail("par de releases D085 inválido")
    images = (previous_backend, candidate_backend, previous_debezium, candidate_debezium)
    if any(not IMAGE_RE.fullmatch(value) for value in images) or len(set(images)) != 4:
        fail("D085 exige imagens imutáveis novas de backend e CDC")

    def inventory(documents, release_id, backend, debezium):
        indexed = {}
        for document in documents:
            normalized = normalize_heartbeat_release(document, release_id, backend, debezium)
            key = (normalized.get("kind"), normalized.get("metadata", {}).get("namespace"),
                   normalized.get("metadata", {}).get("name"))
            if key in indexed:
                fail("recurso duplicado no bundle D085")
            indexed[key] = normalized
        return indexed

    old = inventory(previous, previous_release, previous_backend, previous_debezium)
    new = inventory(candidate, candidate_release, candidate_backend, candidate_debezium)
    config_key = ("ConfigMap", "blindou-production", "blindou-debezium-v3-config")
    if old.keys() != new.keys() or config_key not in old:
        fail("inventário D085 alterou recursos")
    old_config = old[config_key].get("data", {})
    new_config = new[config_key].get("data", {})
    if set(old_config) != {"application.properties"} or set(new_config) != set(old_config):
        fail("ConfigMap CDC contém chaves inesperadas")
    validate_heartbeat_config(old_config["application.properties"], new_config["application.properties"])
    new_config["application.properties"] = old_config["application.properties"]
    if old != new:
        fail("D085 altera manifesto fora de release, backend, CDC e heartbeat")


def validate_heartbeat_bundles(previous_directory: Path, candidate_directory: Path,
                               previous_release: str, candidate_release: str,
                               previous_backend: str, candidate_backend: str,
                               previous_debezium: str, candidate_debezium: str) -> None:
    """Lê somente caches extraídos e verificados pelo controlador root-only."""
    def inventory(directory: Path) -> dict[str, Path]:
        if directory.is_symlink() or not directory.is_dir():
            fail("cache D085 ausente ou simbólico")
        paths = {}
        for path in directory.rglob("*"):
            if path.is_symlink():
                fail("cache D085 contém link simbólico")
            if path.is_file():
                if path.stat().st_size > 2 * 1024 * 1024:
                    fail("arquivo D085 excede o contrato do bundle")
                paths[path.relative_to(directory).as_posix()] = path
        if len(paths) > 96 or not REQUIRED_FILES.issubset(paths):
            fail("cache D085 tem inventário incompleto ou excessivo")
        workers = {name for name in paths if name.startswith("workers/") and name.endswith(".yaml")}
        if len(workers) != EXPECTED_WORKER_COUNT or set(paths) != REQUIRED_FILES | workers:
            fail("cache D085 possui arquivo fora do contrato")
        return paths

    previous_paths = inventory(previous_directory)
    candidate_paths = inventory(candidate_directory)
    if previous_paths.keys() != candidate_paths.keys():
        fail("arquivos dos bundles D085 divergiram")
    for name in ("dispatch-v3/streams.json", "dispatch-v3/consumers.json"):
        if previous_paths[name].read_bytes() != candidate_paths[name].read_bytes():
            fail("D085 altera streams ou consumers")
    validate_heartbeat_transition(
        load_documents(path for path in previous_paths.values() if path.suffix == ".yaml"),
        load_documents(path for path in candidate_paths.values() if path.suffix == ".yaml"),
        previous_release, candidate_release, previous_backend, candidate_backend,
        previous_debezium, candidate_debezium)


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


def validate_dispatch_v3_contract(destination: Path) -> None:
    try:
        streams = json.loads(
            (destination / "dispatch-v3/streams.json").read_text(encoding="utf-8")
        )
        consumers = json.loads(
            (destination / "dispatch-v3/consumers.json").read_text(encoding="utf-8")
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"contrato JetStream inválido: {error}")
    if not isinstance(streams, list) or {
        stream.get("name") for stream in streams if isinstance(stream, dict)
    } != {
        "BLINDOU_DISPATCH_V3_SCHEDULE",
        "BLINDOU_DISPATCH_V3_WORK",
        "BLINDOU_DISPATCH_V3_RESULTS",
        "BLINDOU_DISPATCH_V3_CONTROL",
        "BLINDOU_DISPATCH_V3_DLQ",
    }:
        fail("inventário de streams Dispatch V3 divergente")
    if json.dumps(streams).count("__STREAM_INCARNATION_UUID__") != 5:
        fail("streams Dispatch V3 não possuem a incarnation operacional")
    if not isinstance(consumers, list) or {
        consumer.get("config", {}).get("durable_name")
        for consumer in consumers
        if isinstance(consumer, dict)
    } != {
        "blindou-sender-v3",
        "blindou-settlement-v3",
        "blindou-projector-v3",
        "blindou-operator-v3",
    }:
        fail("inventário de consumers Dispatch V3 divergente")


def validate_documents(documents: list[dict[str, Any]], release_id: str) -> None:
    deployment_names: set[str] = set()
    worker_names: set[str] = set()
    cloudflared_deployments = 0
    migration_jobs = 0
    dispatch_v3_workloads: set[str] = set()

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

        if (kind, name) in {
            ("StatefulSet", "blindou-debezium-v3"),
            ("Deployment", "blindou-dispatch-authority-v3"),
            ("Deployment", "blindou-dispatch-sender-v3"),
        }:
            dispatch_v3_workloads.add(name)
            pod_spec = document.get("spec", {}).get("template", {}).get("spec", {})
            if pod_spec.get("imagePullSecrets") != [{"name": GHCR_PULL_SECRET}]:
                fail(f"workload Dispatch V3 não usa o pull secret GHCR em {resource}")
            annotations = (
                document.get("spec", {}).get("template", {}).get("metadata", {}).get("annotations", {})
            )
            if annotations.get("blindou.io/activation") != "enabled-in-e5":
                fail(f"marcador de ativação E5 ausente em {resource}")
            if name == "blindou-debezium-v3":
                containers = pod_spec.get("containers", []) or []
                images = {
                    container.get("image")
                    for container in containers
                    if container.get("name") == "debezium"
                }
                if images != {EXPECTED_DEBEZIUM_IMAGE}:
                    fail("digest Debezium diverge da candidata aprovada")
                debezium = next(
                    (container for container in containers if container.get("name") == "debezium"),
                    None,
                )
                environment = {
                    item.get("name"): item.get("value")
                    for item in (debezium or {}).get("env", [])
                }
                if environment.get("JAVA_TOOL_OPTIONS") != (
                    "-Djavax.net.ssl.trustStore=/var/run/blindou/nats/truststore.jks "
                    "-Djavax.net.ssl.trustStoreType=JKS "
                    "-Djavax.net.ssl.trustStorePassword=changeit"
                ):
                    fail("Debezium não fixa truststore JKS da CA NATS")
                truststore = next(
                    (
                        volume
                        for volume in pod_spec.get("volumes", []) or []
                        if volume.get("name") == "nats-truststore"
                    ),
                    None,
                )
                if truststore != {
                    "name": "nats-truststore",
                    "secret": {
                        "secretName": "blindou-debezium-v3",
                        "defaultMode": 288,
                        "items": [{"key": "nats-truststore.jks", "path": "truststore.jks"}],
                    },
                }:
                    fail("volume JKS Debezium diverge do contrato fechado")
            if name in {"blindou-dispatch-authority-v3", "blindou-dispatch-sender-v3"}:
                expected_security = {
                    "runAsNonRoot": True,
                    "runAsUser": 10001,
                    "runAsGroup": 10001,
                    "fsGroup": 10001,
                    "fsGroupChangePolicy": "OnRootMismatch",
                    "seccompProfile": {"type": "RuntimeDefault"},
                }
                if pod_spec.get("securityContext") != expected_security:
                    fail(f"grupo de leitura de Secret diverge em {resource}")
            if name == "blindou-dispatch-sender-v3":
                mounted_secrets = {
                    volume.get("secret", {}).get("secretName")
                    for volume in pod_spec.get("volumes", []) or []
                    if "secret" in volume
                }
                if any("database" in str(secret) for secret in mounted_secrets):
                    fail("sender Dispatch V3 recebeu Secret de banco")

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
    if dispatch_v3_workloads != {
        "blindou-debezium-v3",
        "blindou-dispatch-authority-v3",
        "blindou-dispatch-sender-v3",
    }:
        fail("workloads Dispatch V3 ausentes ou duplicados")


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

    validate_dispatch_v3_contract(destination)
    documents = load_documents(
        path for path in paths if path.suffix in {".yaml", ".yml"}
    )
    validate_documents(documents, release_id)
    print("[blindou-release-verify] bundle assinado em escopo fechado: passed")


if __name__ == "__main__":
    main()
