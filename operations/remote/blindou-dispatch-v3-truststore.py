#!/usr/bin/env python3
"""Cria e verifica o truststore JKS mínimo da CA NATS do Dispatch V3.

O arquivo contém somente uma entrada pública trustedCertEntry. A senha JKS é
pública e convencional; este programa nunca recebe, imprime ou persiste chave
privada, senha operacional ou outro Secret.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys


MAGIC = 0xFEEDFEED
VERSION = 2
ENTRY_TAG_TRUSTED_CERTIFICATE = 2
ALIAS = "blindou-nats-ca"
CERTIFICATE_TYPE = "X.509"
PASSWORD = "changeit"
INTEGRITY_SALT = b"Mighty Aphrodite"
MAX_PEM_BYTES = 64 * 1024
MAX_KEYSTORE_BYTES = 128 * 1024
PEM_PATTERN = re.compile(
    rb"\A[\t\r\n ]*-----BEGIN CERTIFICATE-----\r?\n"
    rb"(?P<body>[A-Za-z0-9+/=\r\n]+)"
    rb"-----END CERTIFICATE-----[\t\r\n ]*\Z"
)


class TruststoreError(RuntimeError):
    """Falha fechada de material público de confiança."""


def read_regular(path: Path, maximum: int) -> bytes:
    try:
        info = path.lstat()
    except OSError as error:
        raise TruststoreError("arquivo de truststore ausente") from error
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise TruststoreError("arquivo de truststore não é regular")
    if info.st_size <= 0 or info.st_size > maximum:
        raise TruststoreError("arquivo de truststore excede o limite fechado")
    try:
        content = path.read_bytes()
    except OSError as error:
        raise TruststoreError("arquivo de truststore não pôde ser lido") from error
    if len(content) != info.st_size:
        raise TruststoreError("arquivo de truststore mudou durante a leitura")
    return content


def certificate_der(ca_pem: Path) -> bytes:
    pem = read_regular(ca_pem, MAX_PEM_BYTES)
    match = PEM_PATTERN.fullmatch(pem)
    if match is None:
        raise TruststoreError("CA NATS deve conter exatamente um certificado PEM")
    try:
        der = base64.b64decode(re.sub(rb"\s+", b"", match.group("body")), validate=True)
    except ValueError as error:
        raise TruststoreError("PEM da CA NATS não codifica DER válido") from error
    if not 128 <= len(der) <= MAX_PEM_BYTES:
        raise TruststoreError("DER da CA NATS possui tamanho inválido")
    checked = subprocess.run(
        ["openssl", "x509", "-in", str(ca_pem), "-noout"],
        check=False,
        capture_output=True,
    )
    if checked.returncode != 0:
        raise TruststoreError("DER da CA NATS não representa certificado X.509")
    return der


def write_utf(value: str) -> bytes:
    encoded = value.encode("ascii")
    if len(encoded) > 0xFFFF:
        raise TruststoreError("campo JKS excede UTF fechado")
    return struct.pack(">H", len(encoded)) + encoded


def checksum(content: bytes) -> bytes:
    # JavaKeyStore antepõe a senha UTF-16BE e a constante histórica antes dos
    # bytes serializados. A ordem é parte do formato JKS, não uma escolha local.
    return hashlib.sha1(
        PASSWORD.encode("utf-16-be") + INTEGRITY_SALT + content
    ).digest()


def encode_jks(der: bytes) -> bytes:
    content = b"".join(
        (
            struct.pack(">I", MAGIC),
            struct.pack(">I", VERSION),
            struct.pack(">I", 1),
            struct.pack(">I", ENTRY_TAG_TRUSTED_CERTIFICATE),
            write_utf(ALIAS),
            struct.pack(">q", 0),
            write_utf(CERTIFICATE_TYPE),
            struct.pack(">I", len(der)),
            der,
        )
    )
    return content + checksum(content)


def read_utf(content: bytes, offset: int) -> tuple[str, int]:
    if offset + 2 > len(content):
        raise TruststoreError("JKS truncado no campo UTF")
    length = struct.unpack_from(">H", content, offset)[0]
    offset += 2
    end = offset + length
    if end > len(content):
        raise TruststoreError("JKS truncado no valor UTF")
    try:
        return content[offset:end].decode("ascii"), end
    except UnicodeDecodeError as error:
        raise TruststoreError("JKS contém UTF não permitido") from error


def verify_jks(keystore: Path, expected_der: bytes) -> None:
    content = read_regular(keystore, MAX_KEYSTORE_BYTES)
    if len(content) < 4 + 4 + 4 + 4 + 2 + 8 + 2 + 4 + 20:
        raise TruststoreError("JKS curto demais")
    signed, observed_checksum = content[:-20], content[-20:]
    if not hmac.compare_digest(checksum(signed), observed_checksum):
        raise TruststoreError("checksum JKS inválido")
    offset = 0
    magic, version, count, entry_tag = struct.unpack_from(">IIII", signed, offset)
    offset += 16
    if (magic, version, count, entry_tag) != (
        MAGIC,
        VERSION,
        1,
        ENTRY_TAG_TRUSTED_CERTIFICATE,
    ):
        raise TruststoreError("estrutura JKS diverge do contrato de uma CA")
    alias, offset = read_utf(signed, offset)
    if alias != ALIAS:
        raise TruststoreError("alias JKS diverge da CA NATS")
    if offset + 8 > len(signed):
        raise TruststoreError("JKS truncado no timestamp")
    timestamp = struct.unpack_from(">q", signed, offset)[0]
    offset += 8
    if timestamp != 0:
        raise TruststoreError("timestamp JKS não é determinístico")
    certificate_type, offset = read_utf(signed, offset)
    if certificate_type != CERTIFICATE_TYPE or offset + 4 > len(signed):
        raise TruststoreError("tipo de certificado JKS inválido")
    certificate_size = struct.unpack_from(">I", signed, offset)[0]
    offset += 4
    end = offset + certificate_size
    if end != len(signed) or certificate_size != len(expected_der):
        raise TruststoreError("certificado JKS possui tamanho divergente")
    if not hmac.compare_digest(signed[offset:end], expected_der):
        raise TruststoreError("certificado JKS diverge da CA NATS")


def write_jks(ca_pem: Path, output: Path) -> None:
    der = certificate_der(ca_pem)
    payload = encode_jks(der)
    try:
        descriptor = os.open(
            output,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
    except OSError as error:
        raise TruststoreError("destino temporário JKS não pôde ser criado") from error
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(output, 0o600)
    except OSError as error:
        try:
            output.unlink(missing_ok=True)
        except OSError:
            pass
        raise TruststoreError("destino temporário JKS não pôde ser escrito") from error
    verify_jks(output, der)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=False)
    operation = parser.add_mutually_exclusive_group(required=True)
    operation.add_argument("--write", action="store_true")
    operation.add_argument("--verify", action="store_true")
    parser.add_argument("--ca-pem", required=True, type=Path)
    parser.add_argument("--keystore", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.write == (args.output is None) or args.verify == (args.keystore is None):
        parser.error("a operação exige exatamente o caminho associado")
    if args.write and args.keystore is not None:
        parser.error("--write não aceita --keystore")
    if args.verify and args.output is not None:
        parser.error("--verify não aceita --output")
    return args


def main() -> int:
    try:
        args = parse_args()
        if args.write:
            write_jks(args.ca_pem, args.output)
        else:
            verify_jks(args.keystore, certificate_der(args.ca_pem))
    except TruststoreError as error:
        print(f"[blindou-dispatch-v3-truststore] ERRO: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
