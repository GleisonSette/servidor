#!/usr/bin/env python3
"""Extrai envelopes de Secret do datactl sem imprimir valores."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import tarfile
from pathlib import Path, PurePosixPath
from typing import NoReturn


PASSWORD = re.compile(rb"^[A-Za-z0-9_-]{43}$")
FOUNDATION_FILES = {
    "server-tls/server-ca.crt",
    "server-tls/client-ca.crt",
    "server-tls/tls.crt",
    "server-tls/tls.key",
    "bootstrap-client/ca.crt",
    "bootstrap-client/tls.crt",
    "bootstrap-client/tls.key",
    "backup-client/ca.crt",
    "backup-client/tls.crt",
    "backup-client/tls.key",
    "superuser/password",
    "role-passwords/migration",
    "role-passwords/runtime",
    "role-passwords/redirector",
    "role-passwords/ml",
    "role-passwords/backup",
    "role-passwords/debezium",
}
RECOVERY_FILES = {"recipient.crt", "recipient.key"}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"[blindou-data-secret-verify] ERRO: {message}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("foundation", "recovery"), required=True)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--extract-dir", required=True, type=Path)
    args = parser.parse_args()
    archive_path = args.archive.resolve()
    output = args.extract_dir.resolve()
    expected = FOUNDATION_FILES if args.mode == "foundation" else RECOVERY_FILES
    if archive_path.stat().st_size > 512 * 1024:
        fail("envelope excede 512 KiB")
    if output.exists() and any(output.iterdir()):
        fail("extract-dir deve estar vazio")
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tarfile.open(archive_path, "r:") as archive:
        members = archive.getmembers()
        files = {member.name for member in members if member.isfile()}
        directories = {member.name.rstrip("/") for member in members if member.isdir()}
        expected_directories = (
            {path.split("/", 1)[0] for path in expected if "/" in path}
            if args.mode == "foundation"
            else set()
        )
        if files != expected or directories != expected_directories:
            fail("envelope não contém exatamente os arquivos autorizados")
        for member in members:
            pure = PurePosixPath(member.name)
            if pure.is_absolute() or ".." in pure.parts or not (
                member.isfile() or member.isdir()
            ):
                fail("envelope contém entrada insegura")
            target = (output / Path(*pure.parts)).resolve()
            if os.path.commonpath((output, target)) != str(output):
                fail("envelope escapou do diretório de extração")
            if member.isdir():
                target.mkdir(mode=0o700, parents=True, exist_ok=True)
                continue
            if member.size == 0 or member.size > 64 * 1024:
                fail("arquivo sensível possui tamanho inválido")
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            source = archive.extractfile(member)
            if source is None:
                fail("entrada regular sem conteúdo")
            with source, target.open("xb") as destination:
                shutil.copyfileobj(source, destination)
            target.chmod(0o600)
    if args.mode == "foundation":
        password_paths = [output / "superuser" / "password"] + sorted(
            (output / "role-passwords").iterdir()
        )
        values = [path.read_bytes() for path in password_paths]
        if any(not PASSWORD.fullmatch(value) for value in values):
            fail("senha não usa exatamente 32 bytes em Base64URL sem padding")
        if len(set(values)) != len(values):
            fail("senhas de papéis devem ser distintas")
    print(f"[blindou-data-secret-verify] envelope {args.mode} válido")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
