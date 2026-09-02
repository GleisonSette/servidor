#!/usr/bin/env python3
"""Deriva uma restauração descartável somente de uma release DRE já validada."""

from __future__ import annotations

from pathlib import Path
import re
import sys
from typing import Any

import yaml


IMAGE_RE = re.compile(r"^[a-z0-9][a-z0-9._:/-]*@sha256:[0-9a-f]{64}$")
OPERATION_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$")
TARGET_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
NAMESPACE = "dre-restore-drill"


def fail(message: str) -> None:
    raise SystemExit(f"[dre-restore-render] ERRO: {message}")


def load_documents(path: Path) -> list[dict[str, Any]]:
    if not path.is_file() or path.is_symlink():
        fail("estágio de plataforma ausente ou simbólico")
    try:
        loaded = list(yaml.safe_load_all(path.read_text(encoding="utf-8-sig")))
    except (UnicodeDecodeError, yaml.YAMLError) as error:
        fail(f"estágio de plataforma inválido: {error}")
    documents = [document for document in loaded if document is not None]
    if not all(isinstance(document, dict) for document in documents):
        fail("estágio de plataforma contém documento não estruturado")
    return documents


def find_configmap(documents: list[dict[str, Any]], name: str) -> dict[str, str]:
    matches = [
        document
        for document in documents
        if document.get("kind") == "ConfigMap"
        and document.get("metadata", {}).get("name") == name
    ]
    if len(matches) != 1:
        fail(f"ConfigMap {name} ausente ou duplicado")
    data = matches[0].get("data")
    if not isinstance(data, dict) or not all(
        isinstance(key, str) and isinstance(value, str) for key, value in data.items()
    ):
        fail(f"ConfigMap {name} possui dados inválidos")
    return data


def metadata(name: str, operation_id: str) -> dict[str, Any]:
    return {
        "name": name,
        "namespace": NAMESPACE,
        "labels": {
            "app.kubernetes.io/name": "dre-restore-postgres",
            "app.kubernetes.io/component": "restore-drill",
            "app.kubernetes.io/part-of": "dre-familiar",
            "app.kubernetes.io/managed-by": "dre-deployctl",
            "dre.familiar/operation-id": operation_id,
        },
    }


def container_security() -> dict[str, Any]:
    return {
        "allowPrivilegeEscalation": False,
        "capabilities": {"drop": ["ALL"]},
        "readOnlyRootFilesystem": True,
    }


def main() -> None:
    if len(sys.argv) != 6:
        fail(
            "uso: dre-restore-render.py PLATFORM POSTGRES_IMAGE OPERATION_ID TARGET OUTPUT"
        )
    platform = Path(sys.argv[1]).resolve(strict=True)
    postgres_image = sys.argv[2]
    operation_id = sys.argv[3]
    target = sys.argv[4]
    output = Path(sys.argv[5]).resolve(strict=False)
    if not IMAGE_RE.fullmatch(postgres_image):
        fail("imagem PostgreSQL sem digest")
    if not OPERATION_RE.fullmatch(operation_id):
        fail("operation ID inválido")
    if target != "latest" and not TARGET_RE.fullmatch(target):
        fail("alvo PITR inválido")
    if output.exists() or output.is_symlink():
        fail("arquivo de saída já existe")
    if not output.parent.is_dir() or output.parent.is_symlink():
        fail("diretório de saída inválido")

    documents = load_documents(platform)
    postgres_config = find_configmap(documents, "dre-postgres-config")
    runtime_config = find_configmap(documents, "dre-runtime-config")
    required_postgres_keys = {
        "postgresql.conf",
        "pg_hba.conf",
        "pg_ident.conf",
        "pgbackrest.conf",
    }
    if set(postgres_config) != required_postgres_keys:
        fail("configuração PostgreSQL da release diverge")
    required_runtime_keys = {
        "backup-s3-endpoint",
        "backup-s3-bucket",
        "backup-s3-region",
        "backup-repository-path",
        "web-origin",
        "rust-log",
        "fcm-enabled",
        "fcm-project-id",
    }
    if set(runtime_config) != required_runtime_keys:
        fail("configuração runtime da release diverge")

    repository_environment: list[dict[str, Any]] = [
        {
            "name": "PGBACKREST_REPO1_S3_ENDPOINT",
            "valueFrom": {
                "configMapKeyRef": {
                    "name": "dre-restore-runtime-config",
                    "key": "backup-s3-endpoint",
                }
            },
        },
        {
            "name": "PGBACKREST_REPO1_S3_BUCKET",
            "valueFrom": {
                "configMapKeyRef": {
                    "name": "dre-restore-runtime-config",
                    "key": "backup-s3-bucket",
                }
            },
        },
        {
            "name": "PGBACKREST_REPO1_S3_REGION",
            "valueFrom": {
                "configMapKeyRef": {
                    "name": "dre-restore-runtime-config",
                    "key": "backup-s3-region",
                }
            },
        },
        {
            "name": "PGBACKREST_REPO1_PATH",
            "valueFrom": {
                "configMapKeyRef": {
                    "name": "dre-restore-runtime-config",
                    "key": "backup-repository-path",
                }
            },
        },
    ]
    init_environment: list[dict[str, Any]] = [
        {"name": "DRE_RESTORE_CONFIRM", "value": "DISPOSABLE_RESTORE"},
        *repository_environment,
    ]
    if target != "latest":
        init_environment.append({"name": "DRE_RESTORE_TARGET_TIME", "value": target})

    volume_mounts = [
        {"name": "postgres-data", "mountPath": "/var/lib/postgresql/data"},
        {
            "name": "postgres-config",
            "mountPath": "/etc/postgresql/dre",
            "readOnly": True,
        },
        {
            "name": "postgres-config",
            "mountPath": "/etc/pgbackrest/pgbackrest.conf",
            "subPath": "pgbackrest.conf",
            "readOnly": True,
        },
        {
            "name": "backup-runtime",
            "mountPath": "/var/run/secrets/dre/backup/s3-key",
            "subPath": "s3-key",
            "readOnly": True,
        },
        {
            "name": "backup-runtime",
            "mountPath": "/var/run/secrets/dre/backup/s3-key-secret",
            "subPath": "s3-key-secret",
            "readOnly": True,
        },
        {
            "name": "backup-runtime",
            "mountPath": "/var/run/secrets/dre/backup/cipher-pass",
            "subPath": "cipher-pass",
            "readOnly": True,
        },
        {
            "name": "postgres-run",
            "mountPath": "/var/run/postgresql",
        },
        {"name": "pgbackrest-spool", "mountPath": "/var/spool/pgbackrest"},
        {"name": "temporary", "mountPath": "/tmp"},
    ]
    restore_documents: list[dict[str, Any]] = [
        {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": metadata("dre-restore-postgres-config", operation_id),
            "data": postgres_config,
        },
        {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": metadata("dre-restore-runtime-config", operation_id),
            "data": runtime_config,
        },
        {
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": metadata("dre-restore-postgres", operation_id),
            "spec": {
                "type": "ClusterIP",
                "clusterIP": "None",
                "selector": {
                    "app.kubernetes.io/name": "dre-restore-postgres",
                    "app.kubernetes.io/component": "restore-drill",
                },
                "ports": [{"name": "postgres", "port": 5432, "targetPort": "postgres"}],
            },
        },
        {
            "apiVersion": "v1",
            "kind": "PersistentVolumeClaim",
            "metadata": metadata("dre-restore-data", operation_id),
            "spec": {
                "accessModes": ["ReadWriteOnce"],
                "storageClassName": "dre-local-delete-drill",
                "resources": {"requests": {"storage": "20Gi"}},
            },
        },
        {
            "apiVersion": "apps/v1",
            "kind": "StatefulSet",
            "metadata": metadata("dre-restore-postgres", operation_id),
            "spec": {
                "serviceName": "dre-restore-postgres",
                "replicas": 1,
                "selector": {
                    "matchLabels": {
                        "app.kubernetes.io/name": "dre-restore-postgres",
                        "app.kubernetes.io/component": "restore-drill",
                    }
                },
                "template": {
                    "metadata": {
                        "labels": {
                            "app.kubernetes.io/name": "dre-restore-postgres",
                            "app.kubernetes.io/component": "restore-drill",
                            "app.kubernetes.io/part-of": "dre-familiar",
                            "app.kubernetes.io/managed-by": "dre-deployctl",
                            "dre.familiar/operation-id": operation_id,
                        }
                    },
                    "spec": {
                        "serviceAccountName": "dre-restore",
                        "imagePullSecrets": [{"name": "dre-registry-pull"}],
                        "automountServiceAccountToken": False,
                        "enableServiceLinks": False,
                        "restartPolicy": "Always",
                        "terminationGracePeriodSeconds": 60,
                        "securityContext": {
                            "runAsNonRoot": True,
                            "runAsUser": 70,
                            "runAsGroup": 70,
                            "fsGroup": 70,
                            "fsGroupChangePolicy": "OnRootMismatch",
                            "seccompProfile": {"type": "RuntimeDefault"},
                        },
                        "initContainers": [
                            {
                                "name": "restore",
                                "image": postgres_image,
                                "imagePullPolicy": "IfNotPresent",
                                "command": ["/usr/local/bin/dre-pgbackrest-restore"],
                                "env": init_environment,
                                "resources": {
                                    "requests": {"cpu": "100m", "memory": "256Mi"},
                                    "limits": {"cpu": "1", "memory": "1536Mi"},
                                },
                                "securityContext": container_security(),
                                "volumeMounts": volume_mounts,
                            }
                        ],
                        "containers": [
                            {
                                "name": "postgres",
                                "image": postgres_image,
                                "imagePullPolicy": "IfNotPresent",
                                "args": [
                                    "-c",
                                    "config_file=/etc/postgresql/dre/postgresql.conf",
                                    "-c",
                                    "archive_mode=off",
                                    "-c",
                                    "archive_command=/bin/false",
                                ],
                                "env": [
                                    {"name": "POSTGRES_USER", "value": "dre_postgres_admin"},
                                    {"name": "POSTGRES_DB", "value": "dre"},
                                    {"name": "PGDATA", "value": "/var/lib/postgresql/data/pgdata"},
                                    {"name": "PGBACKREST_ARCHIVE_ASYNC", "value": "n"},
                                    *repository_environment,
                                    {
                                        "name": "PGBACKREST_REPO1_S3_KEY",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                "name": "dre-backup-runtime",
                                                "key": "s3-key",
                                            }
                                        },
                                    },
                                    {
                                        "name": "PGBACKREST_REPO1_S3_KEY_SECRET",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                "name": "dre-backup-runtime",
                                                "key": "s3-key-secret",
                                            }
                                        },
                                    },
                                    {
                                        "name": "PGBACKREST_REPO1_CIPHER_PASS",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                "name": "dre-backup-runtime",
                                                "key": "cipher-pass",
                                            }
                                        },
                                    },
                                ],
                                "ports": [
                                    {
                                        "name": "postgres",
                                        "containerPort": 5432,
                                        "protocol": "TCP",
                                    }
                                ],
                                "resources": {
                                    "requests": {"cpu": "250m", "memory": "512Mi"},
                                    "limits": {"cpu": "1500m", "memory": "2Gi"},
                                },
                                "securityContext": container_security(),
                                "readinessProbe": {
                                    "exec": {
                                        "command": [
                                            "/usr/bin/psql",
                                            "--no-psqlrc",
                                            "--tuples-only",
                                            "--no-align",
                                            "-h",
                                            "/var/run/postgresql",
                                            "-U",
                                            "dre_postgres_admin",
                                            "-d",
                                            "dre",
                                            "--command=SELECT 1",
                                        ]
                                    },
                                    "failureThreshold": 12,
                                    "periodSeconds": 5,
                                    "timeoutSeconds": 3,
                                },
                                "volumeMounts": volume_mounts,
                            }
                        ],
                        "volumes": [
                            {
                                "name": "postgres-data",
                                "persistentVolumeClaim": {"claimName": "dre-restore-data"},
                            },
                            {
                                "name": "postgres-config",
                                "configMap": {
                                    "name": "dre-restore-postgres-config",
                                    "defaultMode": 0o440,
                                },
                            },
                            {
                                "name": "backup-runtime",
                                "secret": {
                                    "secretName": "dre-backup-runtime",
                                    "defaultMode": 0o440,
                                    "items": [
                                        {"key": "s3-key", "path": "s3-key"},
                                        {
                                            "key": "s3-key-secret",
                                            "path": "s3-key-secret",
                                        },
                                        {
                                            "key": "cipher-pass",
                                            "path": "cipher-pass",
                                        },
                                    ],
                                },
                            },
                            {"name": "postgres-run", "emptyDir": {"medium": "Memory", "sizeLimit": "32Mi"}},
                            {"name": "pgbackrest-spool", "emptyDir": {"sizeLimit": "256Mi"}},
                            {"name": "temporary", "emptyDir": {"sizeLimit": "128Mi"}},
                        ],
                    },
                },
            },
        },
    ]
    output.write_text(
        yaml.safe_dump_all(restore_documents, sort_keys=False, explicit_start=True),
        encoding="utf-8",
        newline="\n",
    )
    output.chmod(0o600)
    print("dre_restore_manifest=passed namespace=dre-restore-drill")


if __name__ == "__main__":
    main()
