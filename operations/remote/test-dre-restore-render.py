#!/usr/bin/env python3
"""Testa o manifesto fechado de restore descartável do DRE."""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml


SCRIPT = Path(__file__).with_name("dre-restore-render.py")
IMAGE = "registry.invalid/dre/postgres@sha256:" + "a" * 64
OPERATION = "20260829T120000Z-abcdef123456"


def platform(path: Path) -> None:
    postgres = {
        "postgresql.conf": "archive_mode = on\n",
        "pg_hba.conf": "local all all peer\n",
        "pg_ident.conf": "dre_local postgres dre_postgres_admin\n",
        "pgbackrest.conf": "[dre]\npg1-path=/var/lib/postgresql/data/pgdata\n",
    }
    runtime = {
        "backup-s3-endpoint": "synthetic.invalid",
        "backup-s3-bucket": "dre-synthetic",
        "backup-s3-region": "auto",
        "backup-repository-path": "/dre-production",
        "web-origin": "https://synthetic.invalid",
        "rust-log": "info",
        "fcm-enabled": "false",
        "fcm-project-id": "",
    }
    path.write_text(
        yaml.safe_dump_all(
            [
                {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "dre-postgres-config"}, "data": postgres},
                {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": "dre-runtime-config"}, "data": runtime},
            ],
            sort_keys=False,
        ),
        encoding="utf-8",
    )


class RestoreRenderTests(unittest.TestCase):
    def test_renders_disposable_pvc_and_disables_archiving(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "platform.yaml"
            output = root / "restore.yaml"
            platform(source)
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(source), IMAGE, OPERATION, "latest", str(output)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            documents = [doc for doc in yaml.safe_load_all(output.read_text()) if doc]
            self.assertFalse(any(doc.get("kind") == "Secret" for doc in documents))
            pvc = next(doc for doc in documents if doc.get("kind") == "PersistentVolumeClaim")
            self.assertEqual(pvc["spec"]["storageClassName"], "dre-local-delete-drill")
            statefulset = next(doc for doc in documents if doc.get("kind") == "StatefulSet")
            pod = statefulset["spec"]["template"]["spec"]
            self.assertEqual(pod["securityContext"]["runAsUser"], 70)
            self.assertEqual(pod["securityContext"]["runAsGroup"], 70)
            self.assertEqual(pod["securityContext"]["fsGroup"], 70)
            self.assertEqual(pod["imagePullSecrets"], [{"name": "dre-registry-pull"}])
            restore = pod["initContainers"][0]
            self.assertEqual(restore["command"], ["/usr/local/bin/dre-pgbackrest-restore"])
            backup_mounts = [
                mount for mount in restore["volumeMounts"]
                if mount["name"] == "backup-runtime"
            ]
            self.assertEqual(
                [(mount["mountPath"], mount["subPath"]) for mount in backup_mounts],
                [
                    ("/var/run/secrets/dre/backup/s3-key", "s3-key"),
                    ("/var/run/secrets/dre/backup/s3-key-secret", "s3-key-secret"),
                    ("/var/run/secrets/dre/backup/cipher-pass", "cipher-pass"),
                ],
            )
            backup_volume = next(
                volume for volume in pod["volumes"]
                if volume["name"] == "backup-runtime"
            )
            self.assertEqual(
                backup_volume["secret"]["items"],
                [
                    {"key": "s3-key", "path": "s3-key"},
                    {"key": "s3-key-secret", "path": "s3-key-secret"},
                    {"key": "cipher-pass", "path": "cipher-pass"},
                ],
            )
            postgres_backup_mounts = [
                mount for mount in pod["containers"][0]["volumeMounts"]
                if mount["name"] == "backup-runtime"
            ]
            self.assertEqual(postgres_backup_mounts, backup_mounts)
            self.assertIn("archive_mode=off", pod["containers"][0]["args"])
            self.assertIn("archive_command=/bin/false", pod["containers"][0]["args"])

    def test_rejects_invalid_pitr_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "platform.yaml"
            platform(source)
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(source), IMAGE, OPERATION, "yesterday", str(root / "restore.yaml")],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
