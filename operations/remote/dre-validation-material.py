#!/usr/bin/env python3
"""Materializa segredos sintéticos de uma validação DRE descartável."""

from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
from urllib.parse import quote


IMAGE_RE = re.compile(r"^[a-z0-9][a-z0-9._:/-]*@sha256:[0-9a-f]{64}$")
REGISTRY_RE = re.compile(r"^[a-z0-9][a-z0-9.-]*(?::[0-9]{1,5})?$")
LOGIN_HOST = "dre-postgres.dre-validation.svc.cluster.local"


def fail(message: str) -> None:
    raise SystemExit(f"[dre-validation-material] ERRO: {message}")


def registry_from_image(image: str) -> str:
    name = image.split("@", 1)[0]
    first = name.split("/", 1)[0]
    if "." in first or ":" in first or first == "localhost":
        return first
    return "docker.io"


def validate_docker_config(path: Path, allowed_registries: set[str]) -> bytes:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 65536:
        fail("dockerconfigjson de origem ausente ou inseguro")
    try:
        raw = path.read_bytes()
        value = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"dockerconfigjson inválido: {error}")
    if not isinstance(value, dict) or set(value) != {"auths"}:
        fail("campos do dockerconfigjson divergem")
    auths = value["auths"]
    if not isinstance(auths, dict) or set(auths) != allowed_registries:
        fail("dockerconfigjson alcança registry fora das imagens da release")
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
            username = credentials.get("username")
            password = credentials.get("password")
            if not isinstance(username, str) or not 1 <= len(username) <= 128:
                fail("username de registry inválido")
            if not isinstance(password, str) or not 16 <= len(password) <= 512:
                fail("password de registry inválido")
    return json.dumps(value, separators=(",", ":"), sort_keys=True).encode("utf-8")


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
        if path.is_symlink() or not path.is_dir() or any(path.iterdir()):
            fail("diretório de saída deve existir vazio ou estar ausente")
        if stat.S_IMODE(path.stat().st_mode) & 0o077:
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
        view = memoryview(data)
        while view:
            written = os.write(descriptor, view)
            if written <= 0:
                fail(f"gravação interrompida: {relative}")
            view = view[written:]
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def main() -> None:
    if len(sys.argv) != 6:
        fail(
            "uso: dre-validation-material.py OUTPUT DOCKERCONFIG "
            "RUST_IMAGE POSTGRES_IMAGE VALIDATION_IMAGE"
        )
    output = Path(sys.argv[1]).resolve(strict=False)
    docker_config_path = Path(sys.argv[2]).resolve(strict=True)
    images = sys.argv[3:6]
    if any(not IMAGE_RE.fullmatch(image) for image in images):
        fail("imagem da validação sem digest imutável")
    registries = {registry_from_image(image) for image in images}
    docker_config = validate_docker_config(docker_config_path, registries)
    ensure_output_directory(output)

    admin_password = generate_secret()
    api_password = generate_secret()
    worker_password = generate_secret()
    backup_password = generate_secret()
    write_secret(output, "registry/.dockerconfigjson", docker_config)
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
        output, "database-access/api-url", database_url("dre_api_runtime", api_password)
    )
    write_secret(
        output,
        "database-access/worker-url",
        database_url("dre_worker_runtime", worker_password),
    )
    write_secret(output, "api-runtime/web-bridge-token", generate_secret(96))
    write_secret(output, "backup-runtime/s3-key", generate_secret())
    write_secret(output, "backup-runtime/s3-key-secret", generate_secret())
    write_secret(output, "backup-runtime/cipher-pass", generate_secret(96))
    write_secret(output, "validation-accounts/primary-password", generate_secret())
    write_secret(output, "validation-accounts/secondary-password", generate_secret())
    print("dre_validation_material=passed synthetic=true")


if __name__ == "__main__":
    main()
