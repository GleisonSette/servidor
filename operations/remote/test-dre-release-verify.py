#!/usr/bin/env python3
"""Testes negativos e positivos do verificador de release DRE."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
from typing import Any
import unittest

import yaml


SCRIPT = Path(__file__).with_name("dre-release-verify.py")
SPEC = importlib.util.spec_from_file_location("dre_release_verify", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("não foi possível carregar o verificador DRE")
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)

REVISION = "a" * 40
RELEASE_ID = "dre-20260829T120000Z-" + REVISION[:12]
RUST_IMAGE = "registry.invalid/dre/app@sha256:" + "b" * 64
POSTGRES_IMAGE = "registry.invalid/dre/postgres@sha256:" + "c" * 64
VALIDATION_IMAGE = "registry.invalid/dre/validation@sha256:" + "d" * 64


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def base_document(kind: str, name: str, namespace: str) -> dict[str, Any]:
    api_versions = {
        "Deployment": "apps/v1",
        "StatefulSet": "apps/v1",
        "Job": "batch/v1",
        "NetworkPolicy": "networking.k8s.io/v1",
        "PodDisruptionBudget": "policy/v1",
        "StorageClass": "storage.k8s.io/v1",
    }
    document: dict[str, Any] = {
        "apiVersion": api_versions.get(kind, "v1"),
        "kind": kind,
        "metadata": {
            "name": name,
            "labels": {"app.kubernetes.io/part-of": "dre-familiar"},
        },
    }
    if kind not in {"Namespace", "StorageClass"}:
        document["metadata"]["namespace"] = namespace
    if kind == "Namespace":
        document["metadata"]["labels"].update(
            {
                "dre.familiar/lifecycle": (
                    "disposable" if name == "dre-validation" else "always-active"
                ),
                "pod-security.kubernetes.io/enforce": "restricted",
                "pod-security.kubernetes.io/enforce-version": "v1.36",
            }
        )
    elif kind == "StorageClass":
        document.update(
            {
                "provisioner": "rancher.io/local-path",
                "reclaimPolicy": "Retain",
            }
        )
    elif kind == "ServiceAccount":
        document["automountServiceAccountToken"] = False
    elif kind == "Service":
        document["spec"] = {
            "type": "ClusterIP",
            "selector": {"app": name},
            "ports": [{"port": 5432 if name == "dre-postgres" else 8080}],
        }
    elif kind == "PersistentVolumeClaim":
        document["spec"] = {
            "storageClassName": (
                "local-path" if namespace == "dre-validation" else "dre-local-retain"
            ),
            "accessModes": ["ReadWriteOnce"],
            "resources": {
                "requests": {
                    "storage": "5Gi" if namespace == "dre-validation" else "20Gi"
                }
            },
        }
    elif kind == "NetworkPolicy":
        document["spec"] = {
            "podSelector": {},
            "policyTypes": ["Ingress", "Egress"],
        }
    elif kind in {"ResourceQuota", "LimitRange", "PodDisruptionBudget", "ConfigMap"}:
        document["spec"] = {}
    return document


def workload_document(
    kind: str, name: str, image: str, container_name: str, namespace: str
) -> dict[str, Any]:
    document = base_document(kind, name, namespace)
    pod_spec = {
        "automountServiceAccountToken": False,
        "restartPolicy": "Never" if kind == "Job" else "Always",
        "securityContext": {
            "runAsNonRoot": True,
            "seccompProfile": {"type": "RuntimeDefault"},
        },
        "containers": [
            {
                "name": container_name,
                "image": image,
                "resources": {
                    "requests": {"cpu": "10m", "memory": "32Mi"},
                    "limits": {"cpu": "100m", "memory": "64Mi"},
                },
                "securityContext": {
                    "allowPrivilegeEscalation": False,
                    "readOnlyRootFilesystem": True,
                    "capabilities": {"drop": ["ALL"]},
                },
            }
        ],
    }
    if name == "dre-database-access":
        pod_spec["initContainers"] = [
            {
                "name": "wait-for-postgres",
                "image": POSTGRES_IMAGE,
                "imagePullPolicy": "IfNotPresent",
                "command": ["/bin/sh", "-ec"],
                "args": [VERIFY.WAIT_FOR_POSTGRES_SCRIPT],
                "resources": {
                    "requests": {"cpu": "10m", "memory": "32Mi"},
                    "limits": {"cpu": "100m", "memory": "64Mi"},
                },
                "securityContext": {
                    "allowPrivilegeEscalation": False,
                    "capabilities": {"drop": ["ALL"]},
                    "readOnlyRootFilesystem": True,
                },
            }
        ]
    document["spec"] = {
        "selector": {"matchLabels": {"app": name}},
        "template": {"metadata": {"labels": {"app": name}}, "spec": pod_spec},
    }
    if kind == "Job":
        document["spec"].pop("selector")
        document["spec"].update(
            {"ttlSecondsAfterFinished": 86400, "activeDeadlineSeconds": 300}
        )
    return document


def write_yaml(path: Path, documents: list[dict[str, Any]]) -> None:
    path.write_text(
        yaml.safe_dump_all(documents, sort_keys=False), encoding="utf-8", newline="\n"
    )


def create_tree(root: Path, schema: int = 1) -> set[str]:
    stage_documents: dict[str, list[dict[str, Any]]] = {}
    stages = VERIFY.PRODUCTION_STAGE_FILES
    if schema == 2:
        stages += VERIFY.VALIDATION_STAGE_FILES
    for stage in stages:
        identities = VERIFY.ALLOWED_IDENTITIES[stage]
        namespace = (
            "dre-validation"
            if stage in VERIFY.VALIDATION_STAGE_FILES
            else "dre-production"
        )
        documents: list[dict[str, Any]] = []
        for kind, name in sorted(identities):
            if kind in {"Deployment", "StatefulSet", "Job"}:
                if name == "dre-postgres":
                    image, container = POSTGRES_IMAGE, "postgres"
                elif name == "dre-worker":
                    image, container = RUST_IMAGE, "worker"
                elif name == "dre-api":
                    image, container = RUST_IMAGE, "api"
                elif name == "dre-database-access":
                    image, container = POSTGRES_IMAGE, "database-access"
                elif name == "dre-validation-bootstrap":
                    image, container = RUST_IMAGE, "bootstrap"
                elif name == "dre-validation-e2e":
                    image, container = VALIDATION_IMAGE, "e2e"
                else:
                    image, container = RUST_IMAGE, "migrate"
                document = workload_document(
                    kind, name, image, container, namespace
                )
            else:
                document = base_document(kind, name, namespace)
            documents.append(document)
        stage_documents[stage] = documents
        write_yaml(root / stage, documents)

    checksums = {stage: sha256(root / stage) for stage in stages}
    release: dict[str, Any] = {
        "schema": schema,
        "generated_at_utc": "2026-08-29T12:00:00+00:00",
        "target": "local-k3s-x86_64",
        "namespace": "dre-production",
        "rust_image": RUST_IMAGE,
        "postgres_image": POSTGRES_IMAGE,
        "web_origin": "https://painel-sintetico.invalid",
        "backup_s3_endpoint": "synthetic.r2.cloudflarestorage.com",
        "backup_s3_bucket": "dre-synthetic",
        "backup_s3_region": "auto",
        "backup_repository_path": "/dre-production",
        "fcm_enabled": False,
        "fcm_project_id": "",
        "stages": list(VERIFY.PRODUCTION_STAGE_FILES),
        "stage_sha256": checksums,
    }
    if schema == 2:
        release.update(
            {
                "migration_count": 9,
                "validation_image": VALIDATION_IMAGE,
                "validation_namespace": "dre-validation",
                "validation_stages": list(VERIFY.VALIDATION_STAGE_FILES),
            }
        )
    (root / "release.json").write_text(
        json.dumps(release),
        encoding="utf-8",
    )
    for directory in ("monitoring", "sbom", "scan"):
        (root / directory).mkdir()
    components = ["rust", "postgres"]
    if schema == 2:
        components.append("validation")
    for component in components:
        (root / "sbom" / f"{component}.spdx.json").write_text(
            json.dumps({"spdxVersion": "SPDX-2.3", "packages": []}), encoding="utf-8"
        )
        (root / "scan" / f"{component}.json").write_text(
            json.dumps({"status": "passed"}), encoding="utf-8"
        )
    supply_images: dict[str, Any] = {}
    component_images = {
        "rust": RUST_IMAGE,
        "postgres": POSTGRES_IMAGE,
        "validation": VALIDATION_IMAGE,
    }
    for component in components:
        image = component_images[component]
        sbom_path = f"sbom/{component}.spdx.json"
        scan_path = f"scan/{component}.json"
        supply_images[component] = {
            "reference": image,
            "platform": "linux/amd64",
            "sbom": {"path": sbom_path, "sha256": sha256(root / sbom_path)},
            "scan": {
                "path": scan_path,
                "sha256": sha256(root / scan_path),
                "status": "passed",
                "critical_vulnerabilities": 0,
                "high_vulnerabilities": 0,
            },
        }
    (root / "supply-chain.json").write_text(
        json.dumps(
            {
                "schema": 1,
                "release_id": RELEASE_ID,
                "source_revision": REVISION,
                "target": "local-k3s-x86_64",
                "images": supply_images,
            }
        ),
        encoding="utf-8",
    )
    alert_rules = [
        {
            "alert": name,
            "expr": 'absent(up{namespace="dre-production"})',
            "for": "1m",
        }
        for name in sorted(VERIFY.EXPECTED_ALERTS)
    ]
    write_yaml(
        root / "monitoring" / "alerts-k3s.yml",
        [{"groups": [{"name": "dre-test", "rules": alert_rules}]}],
    )
    evidence = (
        VERIFY.SCHEMA_2_EVIDENCE_FILES
        if schema == 2
        else VERIFY.SCHEMA_1_EVIDENCE_FILES
    )
    return set(stages) | evidence


def create_archive(
    root: Path, destination: Path, required_files: set[str], traversal: bool = False
) -> None:
    with tarfile.open(destination, "w:gz") as archive:
        for relative in sorted(required_files):
            archive.add(root / relative, arcname=relative, recursive=False)
        if traversal:
            info = tarfile.TarInfo("../escape")
            info.size = 1
            import io

            archive.addfile(info, io.BytesIO(b"x"))


def run_verify(archive: Path, destination: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            str(archive),
            str(destination),
            RELEASE_ID,
            sha256(archive),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


class ReleaseVerifierTests(unittest.TestCase):
    def test_accepts_closed_release_and_rejects_nodeport(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "tree"
            root.mkdir()
            required_files = create_tree(root)
            archive = Path(temporary) / "release.tar.gz"
            create_archive(root, archive, required_files)
            accepted = run_verify(archive, Path(temporary) / "accepted")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

            runtime = list(yaml.safe_load_all((root / "30-runtime.yaml").read_text()))
            service = next(doc for doc in runtime if doc.get("kind") == "Service")
            service["spec"]["type"] = "NodePort"
            write_yaml(root / "30-runtime.yaml", runtime)
            release = json.loads((root / "release.json").read_text())
            release["stage_sha256"]["30-runtime.yaml"] = sha256(root / "30-runtime.yaml")
            (root / "release.json").write_text(json.dumps(release), encoding="utf-8")
            create_archive(root, archive, required_files)
            rejected = run_verify(archive, Path(temporary) / "nodeport")
            self.assertNotEqual(rejected.returncode, 0)

    def test_rejects_traversal_and_high_vulnerability(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "tree"
            root.mkdir()
            required_files = create_tree(root)
            traversal = Path(temporary) / "traversal.tar.gz"
            create_archive(root, traversal, required_files, traversal=True)
            rejected = run_verify(traversal, Path(temporary) / "traversal")
            self.assertNotEqual(rejected.returncode, 0)

            supply = json.loads((root / "supply-chain.json").read_text())
            supply["images"]["rust"]["scan"]["high_vulnerabilities"] = 1
            (root / "supply-chain.json").write_text(json.dumps(supply), encoding="utf-8")
            high = Path(temporary) / "high.tar.gz"
            create_archive(root, high, required_files)
            rejected_high = run_verify(high, Path(temporary) / "high")
            self.assertNotEqual(rejected_high.returncode, 0)

    def test_rejects_inconsistent_fcm_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "tree"
            root.mkdir()
            required_files = create_tree(root)
            release = json.loads((root / "release.json").read_text())
            release["fcm_project_id"] = "unexpected-project"
            (root / "release.json").write_text(json.dumps(release), encoding="utf-8")
            archive = Path(temporary) / "fcm.tar.gz"
            create_archive(root, archive, required_files)
            rejected = run_verify(archive, Path(temporary) / "fcm")
            self.assertNotEqual(rejected.returncode, 0)

    def test_accepts_schema_two_and_rejects_missing_validation_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "tree"
            root.mkdir()
            required_files = create_tree(root, schema=2)
            archive = Path(temporary) / "release-schema-two.tar.gz"
            create_archive(root, archive, required_files)
            accepted = run_verify(archive, Path(temporary) / "accepted-schema-two")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            self.assertIn("schema=2 migrations=9", accepted.stdout)

            missing = set(required_files)
            missing.remove("scan/validation.json")
            create_archive(root, archive, missing)
            rejected = run_verify(archive, Path(temporary) / "missing-validation-scan")
            self.assertNotEqual(rejected.returncode, 0)

    def test_schema_two_rejects_validation_runner_image_on_api(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "tree"
            root.mkdir()
            required_files = create_tree(root, schema=2)
            runtime_path = root / "43-validation-runtime.yaml"
            runtime = list(yaml.safe_load_all(runtime_path.read_text()))
            api = next(
                document
                for document in runtime
                if document.get("kind") == "Deployment"
                and document.get("metadata", {}).get("name") == "dre-api"
            )
            api["spec"]["template"]["spec"]["containers"][0]["image"] = VALIDATION_IMAGE
            write_yaml(runtime_path, runtime)
            release = json.loads((root / "release.json").read_text())
            release["stage_sha256"][runtime_path.name] = sha256(runtime_path)
            (root / "release.json").write_text(json.dumps(release), encoding="utf-8")
            archive = Path(temporary) / "swapped-image.tar.gz"
            create_archive(root, archive, required_files)
            rejected = run_verify(archive, Path(temporary) / "swapped-image")
            self.assertNotEqual(rejected.returncode, 0)

    def test_accepts_legacy_database_access_without_wait_init_container(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "tree"
            root.mkdir()
            required_files = create_tree(root)
            access_path = root / "20-database-access.yaml"
            documents = list(yaml.safe_load_all(access_path.read_text()))
            access = next(document for document in documents if document.get("kind") == "Job")
            access["spec"]["template"]["spec"].pop("initContainers")
            write_yaml(access_path, documents)
            release = json.loads((root / "release.json").read_text())
            release["stage_sha256"][access_path.name] = sha256(access_path)
            (root / "release.json").write_text(json.dumps(release), encoding="utf-8")
            archive = Path(temporary) / "legacy-without-wait.tar.gz"
            create_archive(root, archive, required_files)
            accepted = run_verify(archive, Path(temporary) / "legacy-without-wait")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

    def test_rejects_altered_or_misplaced_database_wait_init_container(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "tree"
            root.mkdir()
            required_files = create_tree(root, schema=2)
            access_path = root / "42-validation-database-access.yaml"
            access_documents = list(yaml.safe_load_all(access_path.read_text()))
            access = next(
                document for document in access_documents if document.get("kind") == "Job"
            )
            wait = access["spec"]["template"]["spec"]["initContainers"][0]
            wait["command"] = ["/bin/sh", "-c"]
            write_yaml(access_path, access_documents)
            release = json.loads((root / "release.json").read_text())
            release["stage_sha256"][access_path.name] = sha256(access_path)
            (root / "release.json").write_text(json.dumps(release), encoding="utf-8")
            altered_archive = Path(temporary) / "altered-wait.tar.gz"
            create_archive(root, altered_archive, required_files)
            altered = run_verify(altered_archive, Path(temporary) / "altered-wait")
            self.assertNotEqual(altered.returncode, 0)

            wait["command"] = ["/bin/sh", "-ec"]
            write_yaml(access_path, access_documents)
            runtime_path = root / "43-validation-runtime.yaml"
            runtime_documents = list(yaml.safe_load_all(runtime_path.read_text()))
            api = next(
                document
                for document in runtime_documents
                if document.get("kind") == "Deployment"
                and document.get("metadata", {}).get("name") == "dre-api"
            )
            api["spec"]["template"]["spec"]["initContainers"] = [dict(wait)]
            write_yaml(runtime_path, runtime_documents)
            release["stage_sha256"][access_path.name] = sha256(access_path)
            release["stage_sha256"][runtime_path.name] = sha256(runtime_path)
            (root / "release.json").write_text(json.dumps(release), encoding="utf-8")
            misplaced_archive = Path(temporary) / "misplaced-wait.tar.gz"
            create_archive(root, misplaced_archive, required_files)
            misplaced = run_verify(
                misplaced_archive, Path(temporary) / "misplaced-wait"
            )
            self.assertNotEqual(misplaced.returncode, 0)


if __name__ == "__main__":
    unittest.main()
