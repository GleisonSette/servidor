#!/usr/bin/env python3
"""Exercita recusas do bundle de dados sem acessar host ou cluster."""

from __future__ import annotations

import hashlib
import io
import json
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
VERIFIER = ROOT / "blindou-data-release-verify.py"
RELEASE = "0123456789abcdef0123456789abcdef01234567"
IMAGE = "ghcr.io/gleisonsette/blindou-postgres@sha256:" + "a" * 64
PLATFORM_DIGEST = "sha256:" + "b" * 64
ATTESTATION_DIGEST = "sha256:" + "c" * 64
BASE_IMAGE = (
    "docker.io/library/postgres@sha256:"
    "a10c981235b4f635e65df0cfb66a5598064628128505dbc6a3ed4ca303717521"
)
SOURCE_INDEX = (
    "docker.io/library/postgres:18.6-bookworm@sha256:"
    "1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af"
)
UPSTREAM_REVISION = "e00e1bd34ec5c8a8e7ad89b273b3d42efaf6d5bc"
DOCKERFILE_SHA256 = "68ae5b1a5a2b2c9d9c339d991d7e3e06fb4298d878ed8ab5fe08cd1a5431dfd2"
TRIVY_IMAGE = (
    "docker.io/aquasec/trivy@sha256:"
    "ac2f9d0197456a8ce460884b113e49d65b667f506c31d014c9955869a7a5d682"
)
DIRECTORIES = ("manifests", "manifests/operations", "evidence", "recovery")
OPERATION_NAMES = (
    "25-pull-proof.yaml",
    "30-bootstrap.yaml",
    "40-backup.yaml",
    "50-restore-foundation.yaml",
    "60-restore-workloads.yaml",
)


def sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def json_bytes(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def yaml_workload(kind: str, name: str) -> bytes:
    api_version = "apps/v1" if kind == "StatefulSet" else "batch/v1"
    return f"""apiVersion: {api_version}
kind: {kind}
metadata:
  name: {name}
  namespace: blindou-data
  labels:
    blindou.io/release: {RELEASE}
spec:
  template:
    spec:
      containers:
        - name: postgres
          image: {IMAGE}
""".encode()


def contents() -> dict[str, bytes]:
    registry = json_bytes(
        {
            "name": IMAGE,
            "manifest": {
                "digest": IMAGE.split("@", 1)[1],
                "manifests": [
                    {
                        "digest": PLATFORM_DIGEST,
                        "platform": {"architecture": "amd64", "os": "linux"},
                    },
                    {
                        "digest": ATTESTATION_DIGEST,
                        "annotations": {
                            "vnd.docker.reference.type": "attestation-manifest",
                            "vnd.docker.reference.digest": PLATFORM_DIGEST,
                        },
                        "platform": {"architecture": "unknown", "os": "unknown"},
                    },
                ],
            },
            "provenance": {
                "SLSA": {
                    "invocation": {
                        "parameters": {
                            "source": RELEASE,
                            "base": BASE_IMAGE,
                        }
                    }
                }
            },
            "sbom": {"SPDX": {"SPDXID": "SPDXRef-DOCUMENT"}},
        }
    )
    sbom = json_bytes(
        {
            "spdxVersion": "SPDX-2.3",
            "SPDXID": "SPDXRef-DOCUMENT",
            "documentDescribes": ["SPDXRef-Image"],
        }
    )
    trivy = json_bytes(
        {
            "ArtifactName": IMAGE,
            "Results": [
                {
                    "Target": IMAGE,
                    "Vulnerabilities": [
                        {
                            "VulnerabilityID": "CVE-SYNTHETIC-UPSTREAM",
                            "Severity": "HIGH",
                            "FixedVersion": "",
                        }
                    ],
                }
            ],
        }
    )
    candidate = json_bytes(
        {
            "schema": 1,
            "subject": {
                "name": "ghcr.io/gleisonsette/blindou-postgres",
                "digest": IMAGE.split("@", 1)[1],
                "reference": IMAGE,
                "platform": "linux/amd64",
            },
            "source": {
                "release_sha": RELEASE,
                "base_image": BASE_IMAGE,
                "source_index": SOURCE_INDEX,
                "upstream_revision": UPSTREAM_REVISION,
                "dockerfile_sha256": DOCKERFILE_SHA256,
            },
            "tools": {"trivy_image": TRIVY_IMAGE, "trivy_version": "0.67.2"},
            "registry_attestations": {
                "inspection_sha256": sha256(registry),
                "provenance": True,
                "sbom": True,
            },
            "evidence": {
                "sbom_sha256": sha256(sbom),
                "trivy_sha256": sha256(trivy),
            },
        }
    )
    files = {
        "manifests/00-postgresql.yaml": (
            b"apiVersion: v1\nkind: ConfigMap\nmetadata:\n"
            b"  name: foundation\n  namespace: blindou-data\n"
        ),
        "manifests/05-postgresql-workload.yaml": yaml_workload(
            "StatefulSet", "blindou-postgresql"
        ),
        "manifests/10-network-policies.yaml": (
            b"apiVersion: networking.k8s.io/v1\nkind: NetworkPolicy\nmetadata:\n"
            b"  name: default-deny\n  namespace: blindou-data\n"
        ),
        "manifests/20-application-egress.yaml": (
            b"apiVersion: networking.k8s.io/v1\nkind: NetworkPolicy\nmetadata:\n"
            b"  name: cutover\n  namespace: blindou-production\n"
            b"  annotations:\n    blindou.io/cutover-only: 'true'\n"
        ),
        "evidence/candidate.json": candidate,
        "evidence/registry-attestations.json": registry,
        "evidence/sbom.spdx.json": sbom,
        "evidence/trivy.json": trivy,
        "recovery/recipient.crt": b"synthetic-public-certificate\n",
        "image.manifest.sig": b"synthetic-signature\n",
    }
    for name in OPERATION_NAMES:
        files[f"manifests/operations/{name}"] = yaml_workload(
            "Job", name.removesuffix(".yaml")
        )
    files["image.manifest"] = (
        "schema=1\n"
        "project=blindou\n"
        f"release_id={RELEASE}\n"
        f"image={IMAGE}\n"
        f"candidate_sha256={sha256(candidate)}\n"
        f"trivy_sha256={sha256(trivy)}\n"
        f"sbom_sha256={sha256(sbom)}\n"
        f"registry_attestations_sha256={sha256(registry)}\n"
    ).encode()
    return files


def replace_trivy(files: dict[str, bytes], report: dict[str, object]) -> None:
    trivy = json_bytes(report)
    candidate = json.loads(files["evidence/candidate.json"])
    candidate["evidence"]["trivy_sha256"] = sha256(trivy)
    candidate_bytes = json_bytes(candidate)
    image_manifest = files["image.manifest"].decode()
    image_manifest = re.sub(
        r"^candidate_sha256=[0-9a-f]{64}$",
        f"candidate_sha256={sha256(candidate_bytes)}",
        image_manifest,
        flags=re.MULTILINE,
    )
    image_manifest = re.sub(
        r"^trivy_sha256=[0-9a-f]{64}$",
        f"trivy_sha256={sha256(trivy)}",
        image_manifest,
        flags=re.MULTILINE,
    )
    files["evidence/trivy.json"] = trivy
    files["evidence/candidate.json"] = candidate_bytes
    files["image.manifest"] = image_manifest.encode()


def archive(path: Path, files: dict[str, bytes], unsafe: str | None = None) -> None:
    with tarfile.open(path, "w:gz") as output:
        for directory in DIRECTORIES:
            info = tarfile.TarInfo(directory)
            info.type = tarfile.DIRTYPE
            info.mode = 0o700
            output.addfile(info)
        for name, content in sorted(files.items()):
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = 0o600
            if unsafe == "link" and name == "image.manifest.sig":
                info.type = tarfile.SYMTYPE
                info.linkname = "image.manifest"
                info.size = 0
                output.addfile(info)
            else:
                output.addfile(info, io.BytesIO(content))
        if unsafe == "extra":
            content = b"forbidden\n"
            info = tarfile.TarInfo("unexpected")
            info.size = len(content)
            output.addfile(info, io.BytesIO(content))
        elif unsafe == "traversal":
            content = b"forbidden\n"
            info = tarfile.TarInfo("../escape")
            info.size = len(content)
            output.addfile(info, io.BytesIO(content))


def outer_manifest(path: Path, archive_path: Path, files: dict[str, bytes]) -> None:
    path.write_text(
        "schema=1\n"
        "project=blindou\n"
        f"release_id={RELEASE}\n"
        f"revision={RELEASE}\n"
        f"image={IMAGE}\n"
        f"bundle_sha256={sha256(archive_path.read_bytes())}\n"
        "recovery_certificate_sha256="
        f"{sha256(files['recovery/recipient.crt'])}\n"
        "source_state=clean\n"
        "cutover_authorized=false\n",
        encoding="utf-8",
    )


def verify(root: Path, files: dict[str, bytes], unsafe: str | None, success: bool) -> None:
    root.mkdir(parents=True, exist_ok=True)
    bundle = root / "bundle.tar.gz"
    manifest = root / "manifest"
    extract = root / "extract"
    archive(bundle, files, unsafe)
    outer_manifest(manifest, bundle, files)
    completed = subprocess.run(
        [
            sys.executable,
            str(VERIFIER),
            "--manifest",
            str(manifest),
            "--archive",
            str(bundle),
            "--extract-dir",
            str(extract),
            "--expect-release",
            RELEASE,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if (completed.returncode == 0) != success:
        raise RuntimeError(f"verificador retornou {completed.returncode}; esperado={success}")


def signature_negative(root: Path) -> None:
    if shutil.which("ssh-keygen") is None:
        raise RuntimeError("ssh-keygen é obrigatório para o teste de assinatura")
    key = root / "signing"
    manifest = root / "signed.manifest"
    allowed = root / "allowed_signers"
    manifest.write_text("authorized\n", encoding="utf-8")
    subprocess.run(
        ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    public = (root / "signing.pub").read_text(encoding="utf-8").strip()
    allowed.write_text(f"blindou-local {public}\n", encoding="utf-8")
    subprocess.run(
        ["ssh-keygen", "-Y", "sign", "-f", str(key), "-n", "blindou-data", str(manifest)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    accepted = subprocess.run(
        [
            "ssh-keygen",
            "-Y",
            "verify",
            "-f",
            str(allowed),
            "-I",
            "blindou-local",
            "-n",
            "blindou-data",
            "-s",
            str(manifest) + ".sig",
        ],
        input=manifest.read_bytes(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if accepted.returncode != 0:
        raise RuntimeError(
            "assinatura válida foi recusada: "
            + accepted.stderr.decode(errors="replace")
        )
    altered = subprocess.run(
        [
            "ssh-keygen",
            "-Y",
            "verify",
            "-f",
            str(allowed),
            "-I",
            "blindou-local",
            "-n",
            "blindou-data-image",
            "-s",
            str(manifest) + ".sig",
        ],
        input=manifest.read_bytes(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if altered.returncode == 0:
        raise RuntimeError("assinatura com namespace divergente foi aceita")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="blindou-data-release-") as raw:
        root = Path(raw)
        valid = contents()
        verify(root / "valid", valid, None, True)
        for index, unsafe in enumerate(("extra", "traversal", "link"), start=1):
            target = root / f"unsafe-{index}"
            target.mkdir()
            verify(target, valid, unsafe, False)
        missing = dict(valid)
        del missing["evidence/registry-attestations.json"]
        target = root / "missing"
        target.mkdir()
        verify(target, missing, None, False)
        divergent = dict(valid)
        divergent["manifests/05-postgresql-workload.yaml"] = divergent[
            "manifests/05-postgresql-workload.yaml"
        ].replace(IMAGE.encode(), ("ghcr.io/other/postgres@sha256:" + "e" * 64).encode())
        target = root / "divergent"
        target.mkdir()
        verify(target, divergent, None, False)
        fixable = dict(valid)
        fixable_report = json.loads(fixable["evidence/trivy.json"])
        fixable_report["Results"][0]["Vulnerabilities"][0]["FixedVersion"] = "1.0.1"
        replace_trivy(fixable, fixable_report)
        target = root / "fixable"
        target.mkdir()
        verify(target, fixable, None, False)
        signature_negative(root)
    print(
        "[test-blindou-data-release-verify] bundle válido e recusas de path, link, "
        "evidência, imagem e assinatura passaram"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
