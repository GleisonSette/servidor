#!/usr/bin/env python3
"""Testa materialização de Secrets DRE sem expor o conteúdo."""

from __future__ import annotations

import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import unquote, urlparse


SCRIPT = Path(__file__).with_name("dre-secret-material.py")
RUST_IMAGE = "registry.invalid/dre/app@sha256:" + "a" * 64
POSTGRES_IMAGE = "registry.invalid/dre/postgres@sha256:" + "b" * 64
WEB_BRIDGE_TOKEN = "synthetic-bridge-token-" + "z" * 80


def valid_input() -> dict:
    auth = base64.b64encode(b"dre-reader:synthetic-registry-token-123456").decode()
    return {
        "schema": 1,
        "registry_dockerconfigjson": {"auths": {"registry.invalid": {"auth": auth}}},
        "web_bridge_token": WEB_BRIDGE_TOKEN,
        "r2": {
            "access_key_id": "SYNTHETICR2KEY123456",
            "secret_access_key": "syntheticR2SecretKey1234567890",
        },
        "fcm_service_account": None,
    }


def run(output: Path, source: dict, fcm_project_id: str = "") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), str(output), RUST_IMAGE, POSTGRES_IMAGE, fcm_project_id],
        input=json.dumps(source),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


class SecretMaterialTests(unittest.TestCase):
    def test_generates_distinct_roles_and_never_echoes_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "secrets"
            source = valid_input()
            result = run(output, source)
            self.assertEqual(result.returncode, 0, result.stderr)
            for forbidden in (
                source["r2"]["access_key_id"],
                source["r2"]["secret_access_key"],
                "synthetic-registry-token",
                source["web_bridge_token"],
            ):
                self.assertNotIn(forbidden, result.stdout + result.stderr)
            self.assertEqual(
                (output / "api-runtime" / "web-bridge-token").read_text(),
                source["web_bridge_token"],
            )
            passwords = [
                (output / "postgres-admin" / "password").read_text(),
                (output / "database-access" / "api-password").read_text(),
                (output / "database-access" / "worker-password").read_text(),
                (output / "database-access" / "backup-password").read_text(),
            ]
            self.assertEqual(len(set(passwords)), 4)
            for relative, role in (
                ("postgres-admin/database-url", "dre_postgres_admin"),
                ("database-access/api-url", "dre_api_runtime"),
                ("database-access/worker-url", "dre_worker_runtime"),
            ):
                parsed = urlparse((output / relative).read_text())
                self.assertEqual(parsed.username, role)
                self.assertGreaterEqual(len(unquote(parsed.password or "")), 64)
                self.assertEqual(parsed.hostname, "dre-postgres.dre-production.svc.cluster.local")
            second = run(output, source)
            self.assertNotEqual(second.returncode, 0)

    def test_rejects_registry_outside_images(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = valid_input()
            source["registry_dockerconfigjson"]["auths"]["unrelated.invalid"] = \
                source["registry_dockerconfigjson"]["auths"]["registry.invalid"]
            result = run(Path(temporary) / "secrets", source)
            self.assertNotEqual(result.returncode, 0)

    def test_rejects_missing_or_weak_bridge_token(self) -> None:
        for mutation in ("missing", "short", "invalid"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                source = valid_input()
                if mutation == "missing":
                    del source["web_bridge_token"]
                elif mutation == "short":
                    source["web_bridge_token"] = "too-short-bridge-token"
                else:
                    source["web_bridge_token"] = "x" * 64 + "\n"
                result = run(Path(temporary) / "secrets", source)
                self.assertNotEqual(result.returncode, 0)
                supplied_token = source.get("web_bridge_token")
                if supplied_token:
                    self.assertNotIn(str(supplied_token), result.stderr)

    def test_rejects_fcm_project_outside_release(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = valid_input()
            source["fcm_service_account"] = {
                "type": "service_account",
                "project_id": "other-project",
                "private_key_id": "synthetic-key-id",
                "private_key": "-----BEGIN PRIVATE KEY-----\nsynthetic\n-----END PRIVATE KEY-----\n",
                "client_email": "worker@other-project.iam.gserviceaccount.com",
                "client_id": "1234567890",
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
                "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
                "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/worker",
            }
            result = run(Path(temporary) / "secrets", source, "dre-project")
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
