#!/usr/bin/env python3
"""Testes do envelope sensível do datactl sem usar valores operacionais."""

from __future__ import annotations

import io
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
VERIFIER = ROOT / "blindou-data-secret-verify.py"
PASSWORD_PATHS = (
    "superuser/password",
    "role-passwords/migration",
    "role-passwords/runtime",
    "role-passwords/redirector",
    "role-passwords/ml",
    "role-passwords/backup",
    "role-passwords/debezium",
)
FOUNDATION_FILES = (
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
    *PASSWORD_PATHS,
)


def foundation_values() -> dict[str, bytes]:
    values = {
        path: f"synthetic-{path}\n".encode()
        for path in FOUNDATION_FILES
        if path not in PASSWORD_PATHS
    }
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    for index, path in enumerate(PASSWORD_PATHS):
        values[path] = "".join(
            alphabet[(index * 7 + offset) % len(alphabet)] for offset in range(43)
        ).encode()
    return values


def create_archive(
    path: Path, values: dict[str, bytes], unsafe: str | None = None
) -> None:
    directories = sorted(
        {name.split("/", 1)[0] for name in values if "/" in name}
    )
    with tarfile.open(path, "w:") as output:
        for directory in directories:
            info = tarfile.TarInfo(directory)
            info.type = tarfile.DIRTYPE
            output.addfile(info)
        for name, content in sorted(values.items()):
            info = tarfile.TarInfo(name)
            info.size = len(content)
            if unsafe == "link" and name == "server-tls/tls.key":
                info.type = tarfile.SYMTYPE
                info.linkname = "tls.crt"
                info.size = 0
                output.addfile(info)
            else:
                output.addfile(info, io.BytesIO(content))
        if unsafe in {"extra", "traversal"}:
            content = b"forbidden\n"
            info = tarfile.TarInfo("unexpected" if unsafe == "extra" else "../escape")
            info.size = len(content)
            output.addfile(info, io.BytesIO(content))


def verify(
    root: Path,
    mode: str,
    values: dict[str, bytes],
    success: bool,
    unsafe: str | None = None,
) -> None:
    root.mkdir(parents=True)
    archive = root / "envelope.tar"
    create_archive(archive, values, unsafe)
    completed = subprocess.run(
        [
            sys.executable,
            str(VERIFIER),
            "--mode",
            mode,
            "--archive",
            str(archive),
            "--extract-dir",
            str(root / "extract"),
        ],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if (completed.returncode == 0) != success:
        raise RuntimeError(
            f"envelope {mode} retornou {completed.returncode}; esperado={success}"
        )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="blindou-data-secret-") as raw:
        root = Path(raw)
        valid = foundation_values()
        verify(root / "valid", "foundation", valid, True)
        for index, unsafe in enumerate(("extra", "traversal", "link"), start=1):
            verify(root / f"unsafe-{index}", "foundation", valid, False, unsafe)
        duplicate = dict(valid)
        duplicate["role-passwords/debezium"] = duplicate["role-passwords/backup"]
        verify(root / "duplicate", "foundation", duplicate, False)
        malformed = dict(valid)
        malformed["role-passwords/ml"] = b"too-short"
        verify(root / "malformed", "foundation", malformed, False)
        recovery = {
            "recipient.crt": b"synthetic-recipient-certificate\n",
            "recipient.key": b"synthetic-recipient-private-material\n",
        }
        verify(root / "recovery", "recovery", recovery, True)
        verify(root / "recovery-extra", "recovery", recovery, False, "extra")
    print(
        "[test-blindou-data-secret-verify] envelopes válidos e recusas de "
        "estrutura/senhas passaram"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
