#!/usr/bin/env python3
"""Valida e extrai um bundle assinado do PostgreSQL dedicado."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import tarfile
from pathlib import Path, PurePosixPath
from typing import Any, NoReturn

import yaml


SHA40 = re.compile(r"^[0-9a-f]{40}$")
DIGEST_IMAGE = re.compile(
    r"^ghcr\.io/gleisonsette/blindou-postgres@sha256:[0-9a-f]{64}$"
)
EXPECTED_FILES = {
    "manifests/00-postgresql.yaml",
    "manifests/05-postgresql-workload.yaml",
    "manifests/10-network-policies.yaml",
    "manifests/20-application-egress.yaml",
    "manifests/operations/30-bootstrap.yaml",
    "manifests/operations/25-pull-proof.yaml",
    "manifests/operations/40-backup.yaml",
    "manifests/operations/50-restore-foundation.yaml",
    "manifests/operations/60-restore-workloads.yaml",
    "evidence/candidate.json",
    "evidence/registry-attestations.json",
    "evidence/sbom.spdx.json",
    "evidence/trivy.json",
    "recovery/recipient.crt",
    "image.manifest",
    "image.manifest.sig",
}
EXPECTED_DIRECTORIES = {"manifests", "manifests/operations", "evidence", "recovery"}
EXPECTED_BASE_IMAGE = (
    "docker.io/library/postgres@sha256:"
    "a10c981235b4f635e65df0cfb66a5598064628128505dbc6a3ed4ca303717521"
)
EXPECTED_SOURCE_INDEX = (
    "docker.io/library/postgres:18.6-bookworm@sha256:"
    "1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af"
)
EXPECTED_UPSTREAM_REVISION = "e00e1bd34ec5c8a8e7ad89b273b3d42efaf6d5bc"
EXPECTED_DOCKERFILE_SHA256 = (
    "68ae5b1a5a2b2c9d9c339d991d7e3e06fb4298d878ed8ab5fe08cd1a5431dfd2"
)
EXPECTED_TRIVY_IMAGE = (
    "docker.io/aquasec/trivy@sha256:"
    "ac2f9d0197456a8ce460884b113e49d65b667f506c31d014c9955869a7a5d682"
)


def fail(message: str) -> NoReturn:
    raise SystemExit(f"[blindou-data-release-verify] ERRO: {message}")


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def key_values(path: Path, expected: set[str]) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        key, separator, value = raw.partition("=")
        if not separator or key not in expected or key in values or not value:
            fail(f"contrato inválido em {path.name}")
        values[key] = value
    if set(values) != expected:
        fail(f"campos ausentes em {path.name}")
    return values


def json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"JSON inválido em {path.name}: {error}")
    if not isinstance(value, dict):
        fail(f"JSON raiz inválido em {path.name}")
    return value


def validate_evidence(root: Path, image: str, release: str) -> None:
    evidence = root / "evidence"
    candidate = json_object(evidence / "candidate.json")
    if candidate.get("schema") != 1 or candidate.get("subject") != {
        "name": "ghcr.io/gleisonsette/blindou-postgres",
        "digest": image.split("@", 1)[1],
        "reference": image,
        "platform": "linux/amd64",
    }:
        fail("sujeito da candidata divergente")
    source = candidate.get("source", {})
    expected_source = {
        "release_sha": release,
        "base_image": EXPECTED_BASE_IMAGE,
        "source_index": EXPECTED_SOURCE_INDEX,
        "upstream_revision": EXPECTED_UPSTREAM_REVISION,
        "dockerfile_sha256": EXPECTED_DOCKERFILE_SHA256,
    }
    if source != expected_source:
        fail("evidência pertence a outro SHA")
    if candidate.get("tools") != {
        "trivy_image": EXPECTED_TRIVY_IMAGE,
        "trivy_version": "0.67.2",
    }:
        fail("ferramenta de scan divergente")
    base_image = EXPECTED_BASE_IMAGE
    registry_path = evidence / "registry-attestations.json"
    if candidate.get("registry_attestations") != {
        "inspection_sha256": hash_file(registry_path),
        "provenance": True,
        "sbom": True,
    }:
        fail("attestations de registry ausentes")
    hashes = candidate.get("evidence")
    if hashes != {
        "sbom_sha256": hash_file(evidence / "sbom.spdx.json"),
        "trivy_sha256": hash_file(evidence / "trivy.json"),
    }:
        fail("hashes da evidência divergentes")
    trivy = json_object(evidence / "trivy.json")
    if trivy.get("ArtifactName") != image:
        fail("scan não pertence à candidata")
    for result in trivy.get("Results") or []:
        if result.get("Secrets"):
            fail("scan contém segredo")
        if any(
            str(item.get("Severity", "")).upper() in {"HIGH", "CRITICAL"}
            and str(item.get("FixedVersion", "")).strip()
            for item in result.get("Vulnerabilities") or []
        ):
            fail("scan contém HIGH/CRITICAL corrigível")
    sbom = json_object(evidence / "sbom.spdx.json")
    if sbom.get("spdxVersion") != "SPDX-2.3" or not sbom.get("documentDescribes"):
        fail("SBOM SPDX divergente")
    registry = json_object(registry_path)
    manifest = registry.get("manifest", registry.get("Manifest"))
    provenance = registry.get("provenance", registry.get("Provenance"))
    registry_sbom = registry.get("sbom", registry.get("SBOM"))
    if (
        registry.get("name", registry.get("Name")) != image
        or not isinstance(manifest, dict)
        or manifest.get("digest") != image.split("@", 1)[1]
    ):
        fail("inspeção do registry pertence a outro digest")
    descriptors = manifest.get("manifests")
    if not isinstance(descriptors, list):
        fail("índice OCI sem descritores")
    platforms = [
        descriptor
        for descriptor in descriptors
        if descriptor.get("platform") == {"architecture": "amd64", "os": "linux"}
    ]
    if len(platforms) != 1:
        fail("índice OCI não contém um único linux/amd64")
    attestations = [
        descriptor
        for descriptor in descriptors
        if descriptor.get("annotations", {}).get("vnd.docker.reference.type")
        == "attestation-manifest"
        and descriptor.get("annotations", {}).get("vnd.docker.reference.digest")
        == platforms[0].get("digest")
    ]
    if len(attestations) != 1:
        fail("attestation OCI não está ligada ao manifest linux/amd64")
    if not isinstance(provenance, dict) or not isinstance(
        provenance.get("SLSA"), dict
    ):
        fail("proveniência SLSA publicada ausente")
    serialized_provenance = json.dumps(provenance, sort_keys=True)
    if release not in serialized_provenance or base_image not in serialized_provenance:
        fail("proveniência publicada não contém SHA e base esperados")
    if not isinstance(registry_sbom, dict) or registry_sbom.get("SPDX", {}).get(
        "SPDXID"
    ) != "SPDXRef-DOCUMENT":
        fail("SBOM publicada ausente")


def validate_yaml(root: Path, image: str, release: str) -> None:
    foundation_documents = list(
        yaml.safe_load_all(
            (root / "manifests" / "00-postgresql.yaml").read_text(encoding="utf-8")
        )
    )
    workload_documents = list(
        yaml.safe_load_all(
            (root / "manifests" / "05-postgresql-workload.yaml").read_text(
                encoding="utf-8"
            )
        )
    )
    if any(document.get("kind") == "StatefulSet" for document in foundation_documents):
        fail("fundação contém workload antes da prova de pull")
    if len(workload_documents) != 1 or workload_documents[0].get("kind") != "StatefulSet":
        fail("manifest de workload dedicado divergente")
    yaml_paths = sorted((root / "manifests").glob("*.yaml")) + sorted(
        (root / "manifests" / "operations").glob("*.yaml")
    )
    documents: list[dict[str, Any]] = []
    for path in yaml_paths:
        loaded = list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
        if not loaded or any(not isinstance(document, dict) for document in loaded):
            fail(f"YAML vazio ou inválido: {path.name}")
        documents.extend(loaded)
    if any(
        document.get("kind")
        in {"Secret", "CronJob", "DaemonSet", "ClusterRole", "ClusterRoleBinding"}
        for document in documents
    ):
        fail("bundle contém kind proibido")
    if any(
        document.get("metadata", {}).get("namespace")
        not in {"blindou-data", "blindou-production"}
        for document in documents
    ):
        fail("bundle escapou dos namespaces Blindou")
    images: set[str] = set()
    for document in documents:
        pod_spec = None
        if document.get("kind") == "StatefulSet":
            pod_spec = document.get("spec", {}).get("template", {}).get("spec", {})
        elif document.get("kind") == "Job":
            pod_spec = document.get("spec", {}).get("template", {}).get("spec", {})
        if pod_spec is not None:
            for container in pod_spec.get("initContainers", []) + pod_spec.get(
                "containers", []
            ):
                images.add(container.get("image", ""))
    if images != {image}:
        fail("workloads não usam exclusivamente a imagem assinada")
    egress_documents = list(
        yaml.safe_load_all(
            (root / "manifests" / "20-application-egress.yaml").read_text(
                encoding="utf-8"
            )
        )
    )
    if len(egress_documents) != 1 or egress_documents[0].get("metadata", {}).get(
        "annotations", {}
    ).get("blindou.io/cutover-only") != "true":
        fail("rota da aplicação não está marcada cutover-only")
    release_labels = {
        document.get("metadata", {}).get("labels", {}).get("blindou.io/release")
        for document in documents
        if "blindou.io/release" in document.get("metadata", {}).get("labels", {})
    }
    if release_labels != {release}:
        fail("manifests pertencem a outra release")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--extract-dir", required=True, type=Path)
    parser.add_argument("--expect-release", required=True)
    args = parser.parse_args()
    manifest_path = args.manifest.resolve()
    archive_path = args.archive.resolve()
    extract_dir = args.extract_dir.resolve()
    if not SHA40.fullmatch(args.expect_release):
        fail("release esperada inválida")
    if archive_path.stat().st_size > 64 * 1024 * 1024:
        fail("archive excede 64 MiB")
    values = key_values(
        manifest_path,
        {
            "schema",
            "project",
            "release_id",
            "revision",
            "image",
            "bundle_sha256",
            "recovery_certificate_sha256",
            "source_state",
            "cutover_authorized",
        },
    )
    if (
        values["schema"] != "1"
        or values["project"] != "blindou"
        or values["release_id"] != args.expect_release
        or values["revision"] != args.expect_release
        or values["source_state"] != "clean"
        or values["cutover_authorized"] != "false"
        or not DIGEST_IMAGE.fullmatch(values["image"])
        or values["bundle_sha256"] != hash_file(archive_path)
    ):
        fail("manifesto externo divergente")
    if extract_dir.exists() and any(extract_dir.iterdir()):
        fail("extract-dir deve estar vazio")
    extract_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tarfile.open(archive_path, "r:gz") as archive:
        members = archive.getmembers()
        names = {member.name.rstrip("/") for member in members}
        if names != EXPECTED_FILES | EXPECTED_DIRECTORIES:
            fail("archive contém caminho ausente ou extra")
        for member in members:
            pure = PurePosixPath(member.name)
            if (
                pure.is_absolute()
                or ".." in pure.parts
                or not (member.isfile() or member.isdir())
                or member.size > 16 * 1024 * 1024
            ):
                fail("archive contém entrada insegura")
            target = (extract_dir / Path(*pure.parts)).resolve()
            if os.path.commonpath((extract_dir, target)) != str(extract_dir):
                fail("archive escapou do diretório de extração")
            if member.isdir():
                target.mkdir(mode=0o700, parents=True, exist_ok=True)
            else:
                target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    fail("arquivo regular sem conteúdo")
                with source, target.open("xb") as destination:
                    shutil.copyfileobj(source, destination)
                target.chmod(0o600)
    if hash_file(extract_dir / "recovery" / "recipient.crt") != values[
        "recovery_certificate_sha256"
    ]:
        fail("certificado de recuperação diverge do manifesto")
    image_manifest = key_values(
        extract_dir / "image.manifest",
        {
            "schema",
            "project",
            "release_id",
            "image",
            "candidate_sha256",
            "trivy_sha256",
            "sbom_sha256",
            "registry_attestations_sha256",
        },
    )
    expected_image_values = {
        "schema": "1",
        "project": "blindou",
        "release_id": args.expect_release,
        "image": values["image"],
        "candidate_sha256": hash_file(extract_dir / "evidence" / "candidate.json"),
        "trivy_sha256": hash_file(extract_dir / "evidence" / "trivy.json"),
        "sbom_sha256": hash_file(extract_dir / "evidence" / "sbom.spdx.json"),
        "registry_attestations_sha256": hash_file(
            extract_dir / "evidence" / "registry-attestations.json"
        ),
    }
    if image_manifest != expected_image_values:
        fail("manifesto assinado da imagem diverge")
    validate_evidence(extract_dir, values["image"], args.expect_release)
    validate_yaml(extract_dir, values["image"], args.expect_release)
    print(
        f"[blindou-data-release-verify] release={args.expect_release} image={values['image']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
