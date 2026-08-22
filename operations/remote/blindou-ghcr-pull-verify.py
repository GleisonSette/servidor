#!/usr/bin/env python3
"""Baixa e valida integralmente imagens privadas GHCR sem persistir credenciais."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import socket
import ssl
import stat
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


REGISTRY = "https://ghcr.io"
TOKEN_REALM = "https://ghcr.io/token"
SERVICE = "ghcr.io"
USERNAME = "GleisonSette"
RELEASE_PATTERN = re.compile(r"[0-9a-f]{40}")
DIGEST_PATTERN = re.compile(r"sha256:([0-9a-f]{64})")
IMAGE_PATTERN = re.compile(
    r"ghcr\.io/gleisonsette/blindou-(backend|redirector|nats|cloudflared)@"
    r"(sha256:[0-9a-f]{64})"
)
COMPONENTS = ("backend", "redirector", "nats", "cloudflared")
MANIFEST_ACCEPT = ", ".join(
    (
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
    )
)
INDEX_MEDIA_TYPES = {
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
}
MANIFEST_MEDIA_TYPES = {
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
}
MAX_MANIFEST_BYTES = 4 * 1024 * 1024
MAX_BLOB_BYTES = 1024 * 1024 * 1024
MAX_TOTAL_BYTES = 3 * 1024 * 1024 * 1024
DEADLINE_SECONDS = 20 * 60
CHUNK_SIZE = 1024 * 1024


def fail(message: str) -> None:
    raise SystemExit(f"[blindou-ghcr-pull-verify] ERRO: {message}")


class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, new_url):
        parsed = urllib.parse.urlparse(new_url)
        if parsed.scheme != "https" or not parsed.hostname:
            raise urllib.error.HTTPError(new_url, code, "redirect inseguro", headers, fp)
        redirected = super().redirect_request(request, fp, code, msg, headers, new_url)
        if redirected is None:
            return None
        old_host = urllib.parse.urlparse(request.full_url).hostname
        if parsed.hostname != old_host:
            redirected.remove_header("Authorization")
        return redirected


class RegistryClient:
    def __init__(self, token: str) -> None:
        self._pat = token
        self._bearer: dict[str, str] = {}
        self._deadline = time.monotonic() + DEADLINE_SECONDS
        context = ssl.create_default_context()
        self._opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            urllib.request.HTTPSHandler(context=context),
            SafeRedirectHandler(),
        )

    def _remaining_timeout(self) -> float:
        remaining = self._deadline - time.monotonic()
        if remaining <= 0:
            fail("tempo total de pull excedido")
        return min(60.0, remaining)

    def _open(self, request: urllib.request.Request):
        try:
            return self._opener.open(request, timeout=self._remaining_timeout())
        except urllib.error.HTTPError:
            raise
        except (urllib.error.URLError, TimeoutError, socket.timeout, ssl.SSLError) as error:
            raise RuntimeError("falha de rede/TLS no registry") from error

    def _registry_token(self, repository: str, challenge: str) -> str:
        scheme, separator, parameters = challenge.partition(" ")
        if separator != " " or scheme.lower() != "bearer":
            fail("challenge do registry não é Bearer")
        parsed = urllib.request.parse_keqv_list(urllib.request.parse_http_list(parameters))
        expected_scope = f"repository:{repository}:pull"
        if parsed.get("realm") != TOKEN_REALM or parsed.get("service") != SERVICE:
            fail("autoridade do token GHCR divergente")
        if parsed.get("scope") != expected_scope:
            fail("escopo solicitado pelo GHCR diverge do pull esperado")
        query = urllib.parse.urlencode({"service": SERVICE, "scope": expected_scope})
        basic = base64.b64encode(f"{USERNAME}:{self._pat}".encode("utf-8")).decode("ascii")
        request = urllib.request.Request(
            f"{TOKEN_REALM}?{query}",
            headers={
                "Authorization": f"Basic {basic}",
                "Accept": "application/json",
                "User-Agent": "blindou-deployctl/1",
            },
        )
        try:
            with self._open(request) as response:
                body = response.read(1024 * 1024 + 1)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"GHCR recusou a credencial com HTTP {error.code}") from error
        finally:
            basic = ""
        if len(body) > 1024 * 1024:
            fail("resposta do token GHCR excedeu o limite")
        try:
            payload = json.loads(body)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RuntimeError("resposta inválida do token GHCR") from error
        bearer = payload.get("token") or payload.get("access_token")
        if not isinstance(bearer, str) or not (20 <= len(bearer) <= 8192):
            fail("token temporário do registry ausente ou inválido")
        self._bearer[repository] = bearer
        return bearer

    def _registry_request(self, repository: str, path: str, accept: str | None = None):
        url = f"{REGISTRY}/v2/{repository}/{path}"
        headers = {"User-Agent": "blindou-deployctl/1"}
        if accept:
            headers["Accept"] = accept
        bearer = self._bearer.get(repository)
        if bearer:
            headers["Authorization"] = f"Bearer {bearer}"
        request = urllib.request.Request(url, headers=headers)
        try:
            return self._open(request)
        except urllib.error.HTTPError as error:
            if error.code != 401 or bearer:
                raise RuntimeError(f"GHCR respondeu HTTP {error.code}") from error
            challenge = error.headers.get("WWW-Authenticate", "")
            error.close()
            bearer = self._registry_token(repository, challenge)
            headers["Authorization"] = f"Bearer {bearer}"
            try:
                return self._open(urllib.request.Request(url, headers=headers))
            except urllib.error.HTTPError as retry_error:
                raise RuntimeError(f"GHCR respondeu HTTP {retry_error.code}") from retry_error

    def manifest(self, repository: str, digest: str) -> dict:
        with self._registry_request(repository, f"manifests/{digest}", MANIFEST_ACCEPT) as response:
            body = response.read(MAX_MANIFEST_BYTES + 1)
            header_digest = response.headers.get("Docker-Content-Digest")
        if len(body) > MAX_MANIFEST_BYTES:
            fail("manifesto OCI excedeu o limite")
        expected_hex = require_digest(digest)
        if hashlib.sha256(body).hexdigest() != expected_hex:
            fail("conteúdo do manifesto não corresponde ao digest solicitado")
        if header_digest and header_digest != digest:
            fail("digest retornado pelo registry diverge do solicitado")
        try:
            document = json.loads(body)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RuntimeError("manifesto OCI inválido") from error
        if not isinstance(document, dict):
            fail("manifesto OCI não é um objeto")
        return document

    def blob(self, repository: str, digest: str, destination: Path) -> int:
        expected_hex = require_digest(digest)
        hasher = hashlib.sha256()
        size = 0
        with self._registry_request(repository, f"blobs/{digest}") as response:
            with destination.open("xb") as output:
                while True:
                    chunk = response.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    size += len(chunk)
                    if size > MAX_BLOB_BYTES:
                        fail("blob OCI excedeu o limite individual")
                    hasher.update(chunk)
                    output.write(chunk)
        if hasher.hexdigest() != expected_hex:
            fail("blob OCI não corresponde ao digest solicitado")
        return size


def require_digest(value: str) -> str:
    match = DIGEST_PATTERN.fullmatch(value)
    if not match:
        fail("digest OCI inválido")
    return match.group(1)


def select_linux_amd64_manifest(document: dict) -> str | None:
    media_type = document.get("mediaType")
    if media_type in MANIFEST_MEDIA_TYPES:
        return None
    if media_type not in INDEX_MEDIA_TYPES:
        fail("media type OCI não permitido")
    manifests = document.get("manifests")
    if not isinstance(manifests, list):
        fail("índice OCI sem manifests")
    candidates = []
    for entry in manifests:
        if not isinstance(entry, dict):
            continue
        platform = entry.get("platform")
        if not isinstance(platform, dict):
            continue
        if platform.get("os") == "linux" and platform.get("architecture") == "amd64":
            variant = platform.get("variant")
            if variant not in (None, ""):
                continue
            digest = entry.get("digest")
            if isinstance(digest, str):
                require_digest(digest)
                candidates.append(digest)
    if len(candidates) != 1:
        fail("índice OCI precisa conter exatamente um manifesto linux/amd64")
    return candidates[0]


def manifest_blobs(document: dict) -> list[str]:
    if document.get("mediaType") not in MANIFEST_MEDIA_TYPES:
        fail("manifesto de plataforma possui media type inválido")
    config = document.get("config")
    layers = document.get("layers")
    if not isinstance(config, dict) or not isinstance(layers, list):
        fail("manifesto de plataforma sem config ou layers")
    descriptors = [config, *layers]
    digests: list[str] = []
    for descriptor in descriptors:
        if not isinstance(descriptor, dict) or not isinstance(descriptor.get("digest"), str):
            fail("descritor OCI inválido")
        digest = descriptor["digest"]
        require_digest(digest)
        if digest not in digests:
            digests.append(digest)
    if not digests:
        fail("manifesto OCI sem blobs")
    return digests


def validate_output(path: Path) -> None:
    allowed_root = Path("/var/lib/blindou-platform/ghcr-pull-proofs").resolve()
    resolved = path.resolve(strict=True)
    if resolved.parent != allowed_root:
        fail("recibo temporário escapou do diretório fechado")
    metadata = resolved.lstat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0:
        fail("recibo temporário não é arquivo root-owned")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        fail("recibo temporário precisa usar modo 0600")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-id", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--image", action="append", required=True)
    args = parser.parse_args()
    if os.geteuid() != 0 or socket.gethostname() != "apiwpp":
        fail("execução permitida somente como root no host esperado")
    if not RELEASE_PATTERN.fullmatch(args.release_id):
        fail("release_id inválido")
    validate_output(args.output)
    if len(args.image) != len(COMPONENTS):
        fail("eram esperadas exatamente quatro imagens privadas")
    components: dict[str, tuple[str, str]] = {}
    for image in args.image:
        match = IMAGE_PATTERN.fullmatch(image)
        if not match or match.group(1) in components:
            fail("referência GHCR fora do conjunto privado aprovado")
        components[match.group(1)] = (image, match.group(2))
    if set(components) != set(COMPONENTS):
        fail("backend, redirector, NATS e cloudflared são obrigatórios")
    args.components = components
    return args


def main() -> None:
    args = parse_args()
    if sys.stdin.isatty():
        fail("credencial deve chegar por stdin não interativo")
    credential = sys.stdin.readline(4097).rstrip("\r\n")
    if not re.fullmatch(r"ghp_[A-Za-z0-9]{36,251}", credential):
        fail("credencial GHCR ausente ou com formato inválido")
    if sys.stdin.read(1):
        fail("stdin contém dados adicionais")

    client = RegistryClient(credential)
    credential = ""
    total_bytes = 0
    total_blobs = 0
    component_rows: dict[str, tuple[str, str, int, int]] = {}
    with tempfile.TemporaryDirectory(prefix="blindou-ghcr-pull.", dir="/var/tmp") as temporary:
        temporary_root = Path(temporary)
        for component in COMPONENTS:
            image, index_digest = args.components[component]
            repository = f"gleisonsette/blindou-{component}"
            index = client.manifest(repository, index_digest)
            platform_digest = select_linux_amd64_manifest(index)
            if platform_digest is None:
                platform_digest = index_digest
                platform = index
            else:
                platform = client.manifest(repository, platform_digest)
            blobs = manifest_blobs(platform)
            component_bytes = 0
            for position, digest in enumerate(blobs):
                destination = temporary_root / f"{component}-{position:03d}-{digest[7:23]}.blob"
                size = client.blob(repository, digest, destination)
                component_bytes += size
                total_bytes += size
                total_blobs += 1
                if total_bytes > MAX_TOTAL_BYTES:
                    fail("pull completo excedeu o limite total")
            component_rows[component] = (
                image,
                platform_digest,
                len(blobs),
                component_bytes,
            )

    lines = [
        "schema=1",
        f"release_id={args.release_id}",
        f"verified_at={datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
        "registry=ghcr.io",
        "platform=linux/amd64",
        f"images={len(component_rows)}",
        f"blobs={total_blobs}",
        f"bytes={total_bytes}",
    ]
    for component in COMPONENTS:
        image, platform_digest, blobs, size = component_rows[component]
        lines.extend(
            (
                f"{component}_image={image}",
                f"{component}_platform_digest={platform_digest}",
                f"{component}_blobs={blobs}",
                f"{component}_bytes={size}",
            )
        )
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.chmod(args.output, 0o600)
    print(
        "ghcr_candidate_pull=passed "
        f"release_id={args.release_id} images=4 blobs={total_blobs} bytes={total_bytes}"
    )


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        fail("operação cancelada")
    except RuntimeError as error:
        fail(str(error))
