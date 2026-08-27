#!/usr/bin/env python3
"""Verifica e extrai uma release assinada dos controladores SaferWPP."""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
from typing import Any


CONTRACT_VERSION = "saferwpp.controller-release/v1"
TRUST_ROOT_SHA256 = "5c7d39712dc6342fe948dabe984bcc78fa63571c1d27cc6271decfd1d3682a33"
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_FILE_BYTES = 256 * 1024 * 1024
MAX_TOTAL_BYTES = 512 * 1024 * 1024
MAX_MEMBERS = 64
RELEASE_ID = re.compile(r"^swpc-[0-9]{8}T[0-9]{6}Z-([a-f0-9]{12})$")
COMMIT = re.compile(r"^[a-f0-9]{40}$")
TIMESTAMP = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
SHA256 = re.compile(r"^[a-f0-9]{64}$")
TARGET = {
    "hostname": "apiwpp",
    "os": "linux",
    "architecture": "amd64",
    "k3s": "1.36.2",
}
BUILDERS = {
    "go": "golang:1.26.7-alpine3.23@sha256:9002107029a2333e1cf00327799187cd0f31070e97efebdbd3fc929a257e2f63",
    "node": "mirror.gcr.io/library/node:24.18.0-bookworm-slim@sha256:6f7b03f7c2c8e2e784dcf9295400527b9b1270fd37b7e9a7285cf83b6951452d",
    "cosign": "ghcr.io/sigstore/cosign/cosign@sha256:404b8081d833085d12c21cda889c6f2f3731328768257c760e32fcf070be2cf9",
}
LAYOUT = {
    "contract/controller-release.schema.json": 0o644,
    "evidence/controllers.spdx.json": 0o644,
    "evidence/controllers.trivy.json": 0o644,
    "evidence/provenance.json": 0o644,
    "payload/access/saferwpp-access-session": 0o755,
    "payload/bin/saferwpp-backupctl": 0o755,
    "payload/bin/saferwpp-deployctl": 0o755,
    "payload/bin/saferwpp-secretsctl": 0o755,
    "payload/config/backupctl/config.json": 0o644,
    "payload/config/deployctl/config.json": 0o644,
    "payload/config/secretsctl/config.json": 0o644,
    "payload/manifests/deployctl/admission.yaml": 0o644,
    "payload/manifests/deployctl/rbac.yaml": 0o644,
    "payload/manifests/secretsctl/rbac.yaml": 0o644,
    "payload/sudoers/saferwpp-backupctl": 0o440,
    "payload/sudoers/saferwpp-deployctl": 0o440,
    "payload/sudoers/saferwpp-secretsctl": 0o440,
    "payload/tmpfiles/saferwpp-deployctl.conf": 0o644,
    "payload/tmpfiles/saferwpp-platformctl.conf": 0o644,
    "payload/tools/cosign": 0o755,
    "payload/tools/node": 0o755,
    "payload/verify/lab-manifests.mjs": 0o644,
    "payload/verify/lab-release.mjs": 0o644,
    "payload/verify/verify_oci_archive.py": 0o644,
}
METADATA = {"control-release.json": 0o644, "control-release.sig": 0o644}


def fail(message: str) -> None:
    raise ValueError(message)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def read_regular_file(path: Path, maximum_bytes: int, description: str) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            fail(f"{description} não é arquivo regular exclusivo")
        if metadata.st_size <= 0 or metadata.st_size > maximum_bytes:
            fail(f"{description} excede o limite")
        chunks: list[bytes] = []
        remaining = maximum_bytes + 1
        while remaining > 0:
            block = os.read(descriptor, min(1024 * 1024, remaining))
            if not block:
                break
            chunks.append(block)
            remaining -= len(block)
        content = b"".join(chunks)
        if len(content) != metadata.st_size:
            fail(f"{description} mudou durante a leitura")
        return content
    finally:
        os.close(descriptor)


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        + "\n"
    ).encode("utf-8")


def exact_keys(value: dict[str, Any], expected: set[str], description: str) -> None:
    if set(value) != expected:
        fail(f"campos divergentes em {description}")


def safe_member_name(name: str) -> str:
    candidate = PurePosixPath(name)
    if not name or name.startswith("/") or "\\" in name or candidate.is_absolute():
        fail("path absoluto ou vazio no archive")
    if any(part in {"", ".", ".."} for part in candidate.parts):
        fail(f"path não canônico no archive: {name}")
    canonical = candidate.as_posix()
    if canonical != name:
        fail(f"path não canônico no archive: {name}")
    return canonical


def load_archive_bytes(
    archive_bytes: bytes,
) -> tuple[dict[str, tarfile.TarInfo], dict[str, bytes]]:
    metadata: dict[str, tarfile.TarInfo] = {}
    contents: dict[str, bytes] = {}
    member_count = 0
    total_size = 0
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r|gz") as archive:
        for member in archive:
            member_count += 1
            if member_count > MAX_MEMBERS:
                fail("quantidade inválida de membros")
            name = safe_member_name(member.name)
            if name in metadata:
                fail(f"membro duplicado: {name}")
            if not member.isfile() or member.issym() or member.islnk():
                fail(f"tipo de membro recusado: {name}")
            if member.size <= 0 or member.size > MAX_FILE_BYTES:
                fail(f"tamanho de membro inválido: {name}")
            total_size += member.size
            if total_size > MAX_TOTAL_BYTES:
                fail("conteúdo descompactado excede o limite")
            source = archive.extractfile(member)
            if source is None:
                fail(f"membro ilegível: {name}")
            content = source.read(MAX_FILE_BYTES + 1)
            if len(content) != member.size:
                fail(f"tamanho divergente: {name}")
            metadata[name] = member
            contents[name] = content
    if member_count == 0:
        fail("archive vazio")
    expected = set(LAYOUT) | set(METADATA)
    if set(contents) != expected:
        fail("inventário do archive diverge do contrato")
    return metadata, contents


def load_archive(path: Path) -> tuple[dict[str, tarfile.TarInfo], dict[str, bytes]]:
    return load_archive_bytes(read_regular_file(path, MAX_ARCHIVE_BYTES, "archive"))


def verify_scan(content: bytes) -> None:
    scan = json.loads(content)
    if not isinstance(scan, dict) or not isinstance(scan.get("Results"), list):
        fail("scan Trivy inválido")
    for result in scan["Results"]:
        if not isinstance(result, dict):
            fail("resultado Trivy inválido")
        for key in ("Vulnerabilities", "Secrets"):
            if result.get(key) not in (None, []):
                fail(f"scan contém finding em {key}")


def verify_evidence(contents: dict[str, bytes], manifest: dict[str, Any]) -> None:
    sbom = json.loads(contents["evidence/controllers.spdx.json"])
    if not isinstance(sbom, dict) or not str(sbom.get("spdxVersion", "")).startswith(
        "SPDX-"
    ):
        fail("SBOM SPDX inválido")
    verify_scan(contents["evidence/controllers.trivy.json"])
    provenance = json.loads(contents["evidence/provenance.json"])
    expected = {
        "builders": BUILDERS,
        "contractVersion": "saferwpp.controller-provenance/v1",
        "gitCommit": manifest["gitCommit"],
        "target": TARGET,
    }
    if provenance != expected:
        fail("proveniência divergente")


def verify_signature(manifest: bytes, signature: bytes, public_key: bytes) -> None:
    try:
        decoded = base64.b64decode(signature.strip(), validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError("assinatura não é base64 canônico") from error
    if not decoded or len(decoded) > 4096:
        fail("assinatura possui tamanho inválido")
    with tempfile.TemporaryDirectory(prefix="saferwpp-controller-signature-") as name:
        directory = Path(name)
        manifest_path = directory / "control-release.json"
        signature_path = directory / "control-release.sig.bin"
        public_key_path = directory / "cosign.pub"
        manifest_path.write_bytes(manifest)
        signature_path.write_bytes(decoded)
        public_key_path.write_bytes(public_key)
        openssl_binary = "/usr/bin/openssl"
        if os.name == "nt":
            openssl_binary = shutil.which("openssl") or ""
        if not openssl_binary:
            fail("OpenSSL não está disponível")
        result = subprocess.run(
            [
                openssl_binary,
                "dgst",
                "-sha256",
                "-verify",
                str(public_key_path),
                "-signature",
                str(signature_path),
                str(manifest_path),
            ],
            check=False,
            capture_output=True,
            timeout=30,
        )
        if result.returncode != 0:
            fail("assinatura do manifesto é inválida")


def verify_bundle(
    archive: Path,
    public_key: Path,
    archive_sha256: str,
    expected_release: str,
    expected_commit: str,
) -> tuple[dict[str, Any], dict[str, bytes]]:
    if not SHA256.fullmatch(archive_sha256):
        fail("SHA-256 esperado do archive é inválido")
    archive_bytes = read_regular_file(archive, MAX_ARCHIVE_BYTES, "archive")
    if sha256_bytes(archive_bytes) != archive_sha256:
        fail("SHA-256 do archive diverge")
    public_key_bytes = read_regular_file(public_key, 64 * 1024, "chave pública")
    key_hash = sha256_bytes(public_key_bytes)
    if key_hash != TRUST_ROOT_SHA256:
        fail("chave pública não corresponde à trust root SaferWPP")
    metadata, contents = load_archive_bytes(archive_bytes)
    manifest_bytes = contents["control-release.json"]
    manifest = json.loads(manifest_bytes)
    if not isinstance(manifest, dict):
        fail("manifesto não é objeto")
    exact_keys(
        manifest,
        {
            "builders",
            "contractVersion",
            "createdAt",
            "files",
            "gitCommit",
            "releaseId",
            "signerPublicKeySha256",
            "target",
        },
        "manifesto",
    )
    if manifest["contractVersion"] != CONTRACT_VERSION:
        fail("versão de contrato recusada")
    if manifest["gitCommit"] != expected_commit or not COMMIT.fullmatch(expected_commit):
        fail("commit da release diverge do esperado")
    match = RELEASE_ID.fullmatch(expected_release)
    if (
        match is None
        or match.group(1) != expected_commit[:12]
        or manifest["releaseId"] != expected_release
    ):
        fail("release ID diverge do esperado")
    if not isinstance(manifest["createdAt"], str) or not TIMESTAMP.fullmatch(
        manifest["createdAt"]
    ):
        fail("createdAt inválido")
    if manifest["target"] != TARGET or manifest["builders"] != BUILDERS:
        fail("alvo ou builders divergentes")
    if manifest["signerPublicKeySha256"] != key_hash:
        fail("hash da chave pública diverge do manifesto")
    records = manifest["files"]
    if not isinstance(records, list) or len(records) != len(LAYOUT):
        fail("inventário do manifesto inválido")
    seen: set[str] = set()
    for record in records:
        if not isinstance(record, dict):
            fail("registro de arquivo inválido")
        exact_keys(record, {"mode", "path", "sha256", "size"}, "arquivo")
        relative = str(record["path"])
        if relative in seen or relative not in LAYOUT:
            fail(f"path duplicado ou inesperado: {relative}")
        seen.add(relative)
        if record["mode"] != f"{LAYOUT[relative]:04o}":
            fail(f"modo divergente no manifesto: {relative}")
        if metadata[relative].mode & 0o777 != LAYOUT[relative]:
            fail(f"modo divergente no archive: {relative}")
        if not isinstance(record["size"], int) or record["size"] != len(
            contents[relative]
        ):
            fail(f"tamanho divergente: {relative}")
        if not isinstance(record["sha256"], str) or not SHA256.fullmatch(
            record["sha256"]
        ):
            fail(f"hash inválido: {relative}")
        if record["sha256"] != sha256_bytes(contents[relative]):
            fail(f"hash divergente: {relative}")
    if seen != set(LAYOUT):
        fail("inventário incompleto")
    for relative, mode in METADATA.items():
        if metadata[relative].mode & 0o777 != mode:
            fail(f"modo divergente: {relative}")
    if canonical_json(manifest) != manifest_bytes:
        fail("manifesto não está em JSON canônico")
    verify_evidence(contents, manifest)
    verify_signature(manifest_bytes, contents["control-release.sig"], public_key_bytes)
    return manifest, contents


def extract_contents(contents: dict[str, bytes], destination: Path) -> None:
    if destination.exists():
        if destination.is_symlink() or not destination.is_dir() or any(
            destination.iterdir()
        ):
            fail("destino de extração precisa ser diretório vazio")
    else:
        destination.mkdir(parents=True, mode=0o700)
    for relative in sorted(contents):
        target = destination / Path(*PurePosixPath(relative).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            remaining = memoryview(contents[relative])
            while remaining:
                written = os.write(descriptor, remaining)
                if written <= 0:
                    fail(f"falha ao extrair {relative}")
                remaining = remaining[written:]
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        mode = LAYOUT[relative] if relative in LAYOUT else METADATA[relative]
        os.chmod(target, mode)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("public_key", type=Path)
    parser.add_argument("archive_sha256")
    parser.add_argument("release_id")
    parser.add_argument("git_commit")
    parser.add_argument("--extract", type=Path)
    arguments = parser.parse_args()
    try:
        manifest, contents = verify_bundle(
            arguments.archive,
            arguments.public_key,
            arguments.archive_sha256,
            arguments.release_id,
            arguments.git_commit,
        )
        if arguments.extract is not None:
            extract_contents(contents, arguments.extract)
        print(
            json.dumps(
                {
                    "contractVersion": CONTRACT_VERSION,
                    "gitCommit": manifest["gitCommit"],
                    "releaseId": manifest["releaseId"],
                    "status": "passed",
                },
                separators=(",", ":"),
                sort_keys=True,
            )
        )
    except (
        OSError,
        ValueError,
        json.JSONDecodeError,
        tarfile.TarError,
        subprocess.SubprocessError,
    ) as error:
        parser.exit(1, f"[verify-saferwpp-controller-release] ERRO: {error}\n")


if __name__ == "__main__":
    main()
