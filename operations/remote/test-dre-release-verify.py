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


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def base_document(kind: str, name: str) -> dict[str, Any]:
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
        document["metadata"]["namespace"] = "dre-production"
    if kind == "Namespace":
        document["metadata"]["labels"].update(
            {
                "dre.familiar/lifecycle": "always-active",
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
            "storageClassName": "dre-local-retain",
            "accessModes": ["ReadWriteOnce"],
            "resources": {"requests": {"storage": "20Gi"}},
        }
    elif kind == "NetworkPolicy":
        document["spec"] = {
            "podSelector": {},
            "policyTypes": ["Ingress", "Egress"],
        }
    elif kind in {"ResourceQuota", "LimitRange", "PodDisruptionBudget", "ConfigMap"}:
        document["spec"] = {}
    return document


def workload_document(kind: str, name: str, image: str, container_name: str) -> dict[str, Any]:
    document = base_document(kind, name)
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


def create_tree(root: Path) -> None:
    stage_documents: dict[str, list[dict[str, Any]]] = {}
    for stage, identities in VERIFY.ALLOWED_IDENTITIES.items():
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
                else:
                    image, container = RUST_IMAGE, "migrate"
                document = workload_document(kind, name, image, container)
            else:
                document = base_document(kind, name)
            documents.append(document)
        stage_documents[stage] = documents
        write_yaml(root / stage, documents)

    checksums = {stage: sha256(root / stage) for stage in VERIFY.STAGE_FILES}
    (root / "release.json").write_text(
        json.dumps(
            {
                "schema": 1,
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
                "stages": list(VERIFY.STAGE_FILES),
                "stage_sha256": checksums,
            }
        ),
        encoding="utf-8",
    )
    for directory in ("monitoring", "sbom", "scan"):
        (root / directory).mkdir()
    for component in ("rust", "postgres"):
        (root / "sbom" / f"{component}.spdx.json").write_text(
            json.dumps({"spdxVersion": "SPDX-2.3", "packages": []}), encoding="utf-8"
        )
        (root / "scan" / f"{component}.json").write_text(
            json.dumps({"status": "passed"}), encoding="utf-8"
        )
    supply_images: dict[str, Any] = {}
    for component, image in (("rust", RUST_IMAGE), ("postgres", POSTGRES_IMAGE)):
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


def create_archive(root: Path, destination: Path, traversal: bool = False) -> None:
    with tarfile.open(destination, "w:gz") as archive:
        for relative in sorted(VERIFY.REQUIRED_FILES):
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
            create_tree(root)
            archive = Path(temporary) / "release.tar.gz"
            create_archive(root, archive)
            accepted = run_verify(archive, Path(temporary) / "accepted")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

            runtime = list(yaml.safe_load_all((root / "30-runtime.yaml").read_text()))
            service = next(doc for doc in runtime if doc.get("kind") == "Service")
            service["spec"]["type"] = "NodePort"
            write_yaml(root / "30-runtime.yaml", runtime)
            release = json.loads((root / "release.json").read_text())
            release["stage_sha256"]["30-runtime.yaml"] = sha256(root / "30-runtime.yaml")
            (root / "release.json").write_text(json.dumps(release), encoding="utf-8")
            create_archive(root, archive)
            rejected = run_verify(archive, Path(temporary) / "nodeport")
            self.assertNotEqual(rejected.returncode, 0)

    def test_rejects_traversal_and_high_vulnerability(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "tree"
            root.mkdir()
            create_tree(root)
            traversal = Path(temporary) / "traversal.tar.gz"
            create_archive(root, traversal, traversal=True)
            rejected = run_verify(traversal, Path(temporary) / "traversal")
            self.assertNotEqual(rejected.returncode, 0)

            supply = json.loads((root / "supply-chain.json").read_text())
            supply["images"]["rust"]["scan"]["high_vulnerabilities"] = 1
            (root / "supply-chain.json").write_text(json.dumps(supply), encoding="utf-8")
            high = Path(temporary) / "high.tar.gz"
            create_archive(root, high)
            rejected_high = run_verify(high, Path(temporary) / "high")
            self.assertNotEqual(rejected_high.returncode, 0)

    def test_rejects_inconsistent_fcm_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "tree"
            root.mkdir()
            create_tree(root)
            release = json.loads((root / "release.json").read_text())
            release["fcm_project_id"] = "unexpected-project"
            (root / "release.json").write_text(json.dumps(release), encoding="utf-8")
            archive = Path(temporary) / "fcm.tar.gz"
            create_archive(root, archive)
            rejected = run_verify(archive, Path(temporary) / "fcm")
            self.assertNotEqual(rejected.returncode, 0)


if __name__ == "__main__":
    unittest.main()
