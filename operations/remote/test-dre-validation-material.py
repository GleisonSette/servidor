#!/usr/bin/env python3
"""Testes do material sintético descartável do controlador DRE."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("dre-validation-material.py")
RUST_IMAGE = "registry.invalid/dre/app@sha256:" + "a" * 64
POSTGRES_IMAGE = "registry.invalid/dre/postgres@sha256:" + "b" * 64
VALIDATION_IMAGE = "registry.invalid/dre/validation@sha256:" + "c" * 64


def run_material(
    output: Path, docker_config: Path
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            str(output),
            str(docker_config),
            RUST_IMAGE,
            POSTGRES_IMAGE,
            VALIDATION_IMAGE,
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


class ValidationMaterialTests(unittest.TestCase):
    def test_generates_exact_synthetic_inventory_without_echoing_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            docker_config = root / "config.json"
            docker_config.write_text(
                json.dumps(
                    {
                        "auths": {
                            "registry.invalid": {
                                "username": "synthetic-user",
                                "password": "synthetic-password-1234",
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            output = root / "output"
            result = run_material(output, docker_config)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                result.stdout.strip(),
                "dre_validation_material=passed synthetic=true",
            )
            expected = {
                "registry/.dockerconfigjson",
                "postgres-admin/password",
                "postgres-admin/database-url",
                "database-access/api-password",
                "database-access/worker-password",
                "database-access/backup-password",
                "database-access/api-url",
                "database-access/worker-url",
                "api-runtime/web-bridge-token",
                "backup-runtime/s3-key",
                "backup-runtime/s3-key-secret",
                "backup-runtime/cipher-pass",
                "validation-accounts/primary-password",
                "validation-accounts/secondary-password",
            }
            actual = {
                str(path.relative_to(output)).replace("\\", "/")
                for path in output.rglob("*")
                if path.is_file()
            }
            self.assertEqual(actual, expected)
            if os.name == "posix":
                for path in output.rglob("*"):
                    if path.is_file():
                        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            else:
                source = SCRIPT.read_text(encoding="utf-8")
                self.assertIn("os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600", source)
            api_url = (output / "database-access/api-url").read_text()
            self.assertIn("dre-postgres.dre-validation.svc.cluster.local", api_url)
            primary = (output / "validation-accounts/primary-password").read_text()
            self.assertNotIn(primary, result.stdout + result.stderr)

    def test_rejects_registry_scope_outside_release_images(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            docker_config = root / "config.json"
            docker_config.write_text(
                json.dumps(
                    {
                        "auths": {
                            "registry.invalid": {
                                "username": "synthetic-user",
                                "password": "synthetic-password-1234",
                            },
                            "unrelated.invalid": {
                                "username": "synthetic-user",
                                "password": "synthetic-password-1234",
                            },
                        }
                    }
                ),
                encoding="utf-8",
            )
            result = run_material(root / "output", docker_config)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
