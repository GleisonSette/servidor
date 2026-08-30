#!/usr/bin/env python3
"""Materializa segredos iniciais DRE em arquivos root-only, sem ecoar valores."""

from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
from typing import Any
from urllib.parse import quote


PORTABLE_SECRET_RE = re.compile(r"^[A-Za-z0-9_+=/-]{16,512}$")
BRIDGE_TOKEN_MIN_LENGTH = 64
REGISTRY_RE = re.compile(r"^[a-z0-9][a-z0-9.-]*(?::[0-9]{1,5})?$")
PROJECT_ID_RE = re.compile(r"^[a-z][a-z0-9-]{4,29}$")
LOGIN_HOST = "dre-postgres.dre-production.svc.cluster.local"


def fail(message: str) -> None:
    raise SystemExit(f"[dre-secret-material] ERRO: {message}")


def exact_keys(value: dict[str, Any], expected: set[str], description: str) -> None:
    if set(value) != expected:
        fail(f"campos de {description} divergem do contrato")


def read_input() -> dict[str, Any]:
    try:
        value = json.load(sys.stdin)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"entrada JSON inválida: {error}")
    if not isinstance(value, dict):
        fail("entrada deve ser um objeto JSON")
    exact_keys(
        value,
        {
            "schema",
            "registry_dockerconfigjson",
            "web_bridge_token",
            "r2",
            "fcm_service_account",
        },
        "entrada",
    )
    if value["schema"] != 1:
        fail("schema de entrada incompatível")
    return value


def validate_portable_secret(value: Any, name: str) -> str:
    if not isinstance(value, str) or not PORTABLE_SECRET_RE.fullmatch(value):
        fail(f"{name} deve usar o alfabeto portátil e ter entre 16 e 512 bytes")
    return value


def validate_docker_config(value: Any, allowed_registries: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail("registry_dockerconfigjson deve ser objeto")
    exact_keys(value, {"auths"}, "dockerconfigjson")
    auths = value["auths"]
    if not isinstance(auths, dict) or not auths:
        fail("dockerconfigjson não contém auths")
    if set(auths) != allowed_registries:
        fail("dockerconfigjson alcança registry fora das imagens DRE")
    for registry, credentials in auths.items():
        if not REGISTRY_RE.fullmatch(registry):
            fail("hostname de registry inválido")
        if not isinstance(credentials, dict) or not credentials:
            fail("credencial de registry inválida")
        if not set(credentials).issubset({"auth", "username", "password"}):
            fail("dockerconfigjson contém campo não permitido")
        if "auth" in credentials:
            encoded = credentials["auth"]
            if not isinstance(encoded, str) or len(encoded) > 2048:
                fail("auth de registry inválido")
            try:
                decoded = base64.b64decode(encoded, validate=True)
            except (ValueError, base64.binascii.Error):
                fail("auth de registry não usa base64 válido")
            if b":" not in decoded or len(decoded) < 18:
                fail("auth de registry incompleto")
        else:
            validate_portable_secret(credentials.get("password"), "password do registry")
            username = credentials.get("username")
            if not isinstance(username, str) or not 1 <= len(username) <= 128:
                fail("username do registry inválido")
    return value


def validate_fcm(value: Any, expected_project_id: str) -> dict[str, Any] | None:
    if value is None:
        if expected_project_id:
            fail("release exige credencial FCM")
        return None
    if not isinstance(value, dict):
        fail("service account FCM deve ser objeto ou null")
    required = {
        "type",
        "project_id",
        "private_key_id",
        "private_key",
        "client_email",
        "client_id",
        "auth_uri",
        "token_uri",
        "auth_provider_x509_cert_url",
        "client_x509_cert_url",
    }
    if not required.issubset(set(value)):
        fail("service account FCM não contém os campos mínimos")
    if value.get("type") != "service_account":
        fail("tipo da credencial FCM diverge")
    project_id = value.get("project_id")
    if not isinstance(project_id, str) or not PROJECT_ID_RE.fullmatch(project_id):
        fail("project_id FCM inválido")
    if project_id != expected_project_id:
        fail("project_id FCM diverge da release")
    private_key = value.get("private_key")
    private_key_header = "-----BEGIN " + "PRIVATE KEY-----"
    private_key_footer = "-----END " + "PRIVATE KEY-----"
    if (
        not isinstance(private_key, str)
        or private_key_header not in private_key
        or private_key_footer not in private_key
        or len(private_key) > 16384
    ):
        fail("chave privada FCM inválida")
    if value.get("token_uri") != "https://oauth2.googleapis.com/token":
        fail("token_uri FCM inesperada")
    return value


def generate_secret(length: int = 64) -> str:
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+-/="
    return "".join(secrets.choice(alphabet) for _ in range(length))


def database_url(role: str, password: str) -> str:
    return (
        f"postgresql://{role}:{quote(password, safe='')}@{LOGIN_HOST}:5432/dre"
        "?sslmode=disable"
    )


def ensure_output_directory(path: Path) -> None:
    if path.exists():
        if path.is_symlink() or not path.is_dir():
            fail("diretório de saída inválido")
        if any(path.iterdir()):
            fail("diretório de saída deve estar vazio")
        mode = stat.S_IMODE(path.stat().st_mode)
        if mode & 0o077:
            fail("diretório de saída permite acesso de grupo/outros")
    else:
        path.mkdir(mode=0o700, parents=True)


def write_secret(root: Path, relative: str, value: str | bytes) -> None:
    target = root / relative
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if target.exists() or target.is_symlink():
        fail(f"arquivo de saída já existe: {relative}")
    data = value.encode("utf-8") if isinstance(value, str) else value
    descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(descriptor, data)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def registry_from_image(image: str) -> str:
    name = image.split("@", 1)[0]
    first = name.split("/", 1)[0]
    if "." in first or ":" in first or first == "localhost":
        return first
    return "docker.io"


def main() -> None:
    if len(sys.argv) != 5:
        fail("uso: dre-secret-material.py OUTPUT RUST_IMAGE POSTGRES_IMAGE FCM_PROJECT_ID")
    output = Path(sys.argv[1]).resolve(strict=False)
    images = set(sys.argv[2:4])
    for image in images:
        if "@sha256:" not in image:
            fail("imagem sem digest")
    allowed_registries = {registry_from_image(image) for image in images}

    source = read_input()
    docker_config = validate_docker_config(
        source["registry_dockerconfigjson"], allowed_registries
    )
    r2 = source["r2"]
    if not isinstance(r2, dict):
        fail("r2 deve ser objeto")
    exact_keys(r2, {"access_key_id", "secret_access_key"}, "r2")
    r2_key = validate_portable_secret(r2["access_key_id"], "access_key_id R2")
    r2_secret = validate_portable_secret(
        r2["secret_access_key"], "secret_access_key R2"
    )
    bridge_token = validate_portable_secret(
        source["web_bridge_token"], "web_bridge_token"
    )
    if len(bridge_token) < BRIDGE_TOKEN_MIN_LENGTH:
        fail(
            "web_bridge_token deve possuir ao menos "
            f"{BRIDGE_TOKEN_MIN_LENGTH} bytes"
        )
    expected_fcm_project_id = sys.argv[4]
    if expected_fcm_project_id and not PROJECT_ID_RE.fullmatch(expected_fcm_project_id):
        fail("project_id FCM esperado é inválido")
    fcm = validate_fcm(source["fcm_service_account"], expected_fcm_project_id)

    ensure_output_directory(output)
    admin_password = generate_secret()
    api_password = generate_secret()
    worker_password = generate_secret()
    backup_password = generate_secret()

    write_secret(
        output,
        "registry/.dockerconfigjson",
        json.dumps(docker_config, separators=(",", ":"), sort_keys=True),
    )
    write_secret(output, "postgres-admin/password", admin_password)
    write_secret(
        output,
        "postgres-admin/database-url",
        database_url("dre_postgres_admin", admin_password),
    )
    write_secret(output, "database-access/api-password", api_password)
    write_secret(output, "database-access/worker-password", worker_password)
    write_secret(output, "database-access/backup-password", backup_password)
    write_secret(
        output,
        "database-access/api-url",
        database_url("dre_api_runtime", api_password),
    )
    write_secret(
        output,
        "database-access/worker-url",
        database_url("dre_worker_runtime", worker_password),
    )
    write_secret(output, "api-runtime/web-bridge-token", bridge_token)
    write_secret(output, "backup-runtime/s3-key", r2_key)
    write_secret(output, "backup-runtime/s3-key-secret", r2_secret)
    write_secret(output, "backup-runtime/cipher-pass", generate_secret(96))
    if fcm is not None:
        write_secret(
            output,
            "fcm-runtime/service-account.json",
            json.dumps(fcm, separators=(",", ":"), sort_keys=True),
        )

    print(f"dre_secret_material=passed fcm_enabled={str(fcm is not None).lower()}")


if __name__ == "__main__":
    main()
