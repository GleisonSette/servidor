#!/usr/bin/env python3
"""Teste determinístico do truststore JKS público do Dispatch V3."""

from __future__ import annotations

import hashlib
from pathlib import Path
import struct
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent
TOOL = ROOT / "blindou-dispatch-v3-truststore.py"
PUBLIC_CERTIFICATE = ROOT / "blindou-backup-recipient.crt"


def run(*arguments: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [sys.executable, str(TOOL), *arguments], check=False, capture_output=True
    )


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"[test-blindou-dispatch-v3-truststore] ERRO: {message}")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="blindou-dispatch-v3-jks-test.") as temporary:
        root = Path(temporary)
        certificate = root / "synthetic-ca.crt"
        require(PUBLIC_CERTIFICATE.is_file(), "certificado público de fixture ausente")
        certificate.write_bytes(PUBLIC_CERTIFICATE.read_bytes())
        truststore = root / "truststore.jks"
        created = run("--write", "--ca-pem", str(certificate), "--output", str(truststore))
        require(created.returncode == 0 and truststore.is_file(), "JKS positivo não foi criado")
        verified = run("--verify", "--ca-pem", str(certificate), "--keystore", str(truststore))
        require(verified.returncode == 0, "JKS positivo não foi verificado")

        content = truststore.read_bytes()
        signed, digest = content[:-20], content[-20:]
        require(
            struct.unpack_from(">IIII", signed, 0) == (0xFEEDFEED, 2, 1, 2),
            "cabeçalho JKS diverge",
        )
        require(
            hashlib.sha1(
                "changeit".encode("utf-16-be") + b"Mighty Aphrodite" + signed
            ).digest()
            == digest,
            "checksum JKS não segue o formato OpenJDK",
        )
        require(
            hashlib.sha1(signed + "changeit".encode("utf-16-be")).digest() != digest,
            "checksum legado incompatível com OpenJDK foi emitido",
        )

        modified = bytearray(content)
        modified[-1] ^= 1
        truststore.write_bytes(modified)
        checksum_rejected = run(
            "--verify", "--ca-pem", str(certificate), "--keystore", str(truststore)
        )
        require(checksum_rejected.returncode != 0, "checksum JKS alterado foi aceito")

        duplicate = root / "duplicate-ca.crt"
        duplicate.write_bytes(certificate.read_bytes() + certificate.read_bytes())
        duplicate_rejected = run(
            "--write", "--ca-pem", str(duplicate), "--output", str(root / "duplicate.jks")
        )
        require(duplicate_rejected.returncode != 0, "PEM com duas CAs foi aceito")

    print("dispatch_v3_jks_truststore_tests=passed positive=2 refusals=2")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
