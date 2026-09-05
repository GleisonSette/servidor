#!/usr/bin/env python3
"""Provisiona o inventário JetStream V3 por um endpoint local encaminhado."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import socket
import ssl
import uuid
from typing import Any


MAX_FRAME_BYTES = 2 * 1024 * 1024
EXPECTED_STREAM_ORDER = (
    "BLINDOU_DISPATCH_V3_SCHEDULE",
    "BLINDOU_DISPATCH_V3_WORK",
    "BLINDOU_DISPATCH_V3_RESULTS",
    "BLINDOU_DISPATCH_V3_CONTROL",
    "BLINDOU_DISPATCH_V3_DLQ",
)
EXPECTED_CONSUMERS = {
    "blindou-sender-v3",
    "blindou-settlement-v3",
    "blindou-projector-v3",
    "blindou-operator-v3",
}


def fail(message: str) -> None:
    raise SystemExit(f"[blindou-dispatch-v3-jetstream] ERRO: {message}")


class NatsConnection:
    def __init__(
        self,
        host: str,
        port: int,
        user: str,
        password: str,
        ca_file: Path,
        server_name: str,
    ) -> None:
        if host != "127.0.0.1" or not 1 <= port <= 65535:
            fail("o endpoint deve ser loopback IPv4 com porta válida")
        raw = socket.create_connection((host, port), timeout=10)
        raw.settimeout(10)
        self._socket: socket.socket | ssl.SSLSocket = raw
        self._buffer = bytearray()
        first = self._read_line()
        if not first.startswith(b"INFO "):
            fail("handshake NATS inicial inválido")
        context = ssl.create_default_context(cafile=str(ca_file))
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        self._socket = context.wrap_socket(raw, server_hostname=server_name)
        connect = {
            "verbose": False,
            "pedantic": True,
            "tls_required": True,
            "name": "blindou-dispatch-v3-controller",
            "lang": "python-stdlib",
            "version": "1",
            "protocol": 1,
            "echo": True,
            "headers": True,
            "no_responders": True,
            "user": user,
            "pass": password,
        }
        self._send(
            b"CONNECT "
            + json.dumps(connect, separators=(",", ":")).encode("utf-8")
            + b"\r\nPING\r\n"
        )
        self._wait_for_pong()
        self._sid = 0

    def close(self) -> None:
        self._socket.close()
        self._buffer.clear()

    def _send(self, payload: bytes) -> None:
        self._socket.sendall(payload)

    def _fill(self, size: int) -> None:
        while len(self._buffer) < size:
            block = self._socket.recv(64 * 1024)
            if not block:
                fail("conexão NATS encerrada")
            self._buffer.extend(block)
            if len(self._buffer) > MAX_FRAME_BYTES:
                fail("frame NATS excedeu o limite")

    def _read_line(self) -> bytes:
        while True:
            marker = self._buffer.find(b"\r\n")
            if marker >= 0:
                result = bytes(self._buffer[:marker])
                del self._buffer[: marker + 2]
                return result
            self._fill(len(self._buffer) + 1)

    def _read_exact(self, size: int) -> bytes:
        if size < 0 or size > MAX_FRAME_BYTES:
            fail("tamanho de frame NATS inválido")
        self._fill(size + 2)
        result = bytes(self._buffer[:size])
        if self._buffer[size : size + 2] != b"\r\n":
            fail("frame NATS sem terminador")
        del self._buffer[: size + 2]
        return result

    def _wait_for_pong(self) -> None:
        while True:
            line = self._read_line()
            if line == b"PONG":
                return
            if line == b"PING":
                self._send(b"PONG\r\n")
            elif line.startswith(b"-ERR"):
                fail("NATS recusou autenticação ou TLS")

    def _next_message(self) -> tuple[str, bytes]:
        while True:
            line = self._read_line()
            if line == b"PING":
                self._send(b"PONG\r\n")
                continue
            if line in {b"PONG", b"+OK"} or line.startswith(b"INFO "):
                continue
            if line.startswith(b"-ERR"):
                fail("NATS recusou a operação")
            parts = line.split()
            if parts and parts[0] == b"MSG" and len(parts) in {4, 5}:
                return parts[1].decode("ascii"), self._read_exact(int(parts[-1]))
            if parts and parts[0] == b"HMSG" and len(parts) in {5, 6}:
                header_size = int(parts[-2])
                total_size = int(parts[-1])
                frame = self._read_exact(total_size)
                return parts[1].decode("ascii"), frame[header_size:]
            fail("resposta NATS inesperada")

    def request(self, subject: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
        self._sid += 1
        inbox = f"_INBOX.BLINDOU.CONTROLLER.{uuid.uuid4().hex}"
        payload = json.dumps(body or {}, separators=(",", ":")).encode("utf-8")
        command = (
            f"SUB {inbox} {self._sid}\r\nUNSUB {self._sid} 1\r\n"
            f"PUB {subject} {inbox} {len(payload)}\r\n"
        ).encode("ascii")
        self._send(command + payload + b"\r\n")
        response_subject, response = self._next_message()
        if response_subject != inbox:
            fail("resposta JetStream chegou em inbox divergente")
        try:
            document = json.loads(response)
        except json.JSONDecodeError:
            fail("resposta JetStream não é JSON")
        if not isinstance(document, dict):
            fail("resposta JetStream não é objeto")
        return document


def load_json(path: Path) -> list[dict[str, Any]]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"JSON inválido: {error}")
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        fail("inventário deve ser uma lista de objetos")
    return value


def require_success(document: dict[str, Any], operation: str) -> dict[str, Any]:
    if error := document.get("error"):
        description = str(error.get("description", "erro sem descrição"))[:200]
        fail(f"JetStream recusou {operation}: {description}")
    return document


def is_not_found(document: dict[str, Any]) -> bool:
    error = document.get("error")
    return isinstance(error, dict) and int(error.get("code", 0)) == 404


def normalized_field(document: dict[str, Any], field: str) -> Any:
    if field == "sources":
        return document.get(field) or []
    if field == "allow_msg_schedules":
        return bool(document.get(field, False))
    return document.get(field)


def compare_fields(actual: dict[str, Any], expected: dict[str, Any], fields: tuple[str, ...], label: str) -> None:
    divergent = [
        field
        for field in fields
        if normalized_field(actual, field) != normalized_field(expected, field)
    ]
    if divergent:
        fail(f"{label} diverge nos campos: {','.join(divergent)}")


def provision(
    connection: NatsConnection,
    streams_path: Path,
    consumers_path: Path,
    incarnation: str,
    verify_only: bool,
) -> None:
    try:
        uuid.UUID(incarnation)
    except ValueError:
        fail("incarnation JetStream inválida")
    streams = load_json(streams_path)
    if tuple(stream.get("name") for stream in streams) != EXPECTED_STREAM_ORDER:
        fail("ordem ou inventário de streams divergente")
    for source in streams:
        config = json.loads(json.dumps(source).replace("__STREAM_INCARNATION_UUID__", incarnation))
        name = str(config["name"])
        info = connection.request(f"$JS.API.STREAM.INFO.{name}")
        if is_not_found(info):
            if verify_only:
                fail(f"stream {name} ausente")
            response = connection.request(f"$JS.API.STREAM.CREATE.{name}", config)
        else:
            require_success(info, f"info do stream {name}")
            response = (
                info
                if verify_only
                else connection.request(f"$JS.API.STREAM.UPDATE.{name}", config)
            )
        current = require_success(response, f"reconciliação do stream {name}").get("config", {})
        compare_fields(
            current,
            config,
            (
                "name",
                "subjects",
                "retention",
                "discard",
                "max_age",
                "max_bytes",
                "max_msg_size",
                "duplicate_window",
                "storage",
                "num_replicas",
                "metadata",
                "sources",
                "allow_msg_schedules",
            ),
            f"stream {name}",
        )

    consumers = load_json(consumers_path)
    if {item.get("config", {}).get("durable_name") for item in consumers} != EXPECTED_CONSUMERS:
        fail("inventário de consumers divergente")
    for item in consumers:
        stream = str(item.get("stream", ""))
        config = item.get("config", {})
        durable = str(config.get("durable_name", ""))
        if stream not in EXPECTED_STREAM_ORDER or durable not in EXPECTED_CONSUMERS:
            fail("consumer fora do contrato fechado")
        info = connection.request(f"$JS.API.CONSUMER.INFO.{stream}.{durable}")
        if is_not_found(info):
            if verify_only:
                fail(f"consumer {durable} ausente")
            response = connection.request(
                f"$JS.API.CONSUMER.DURABLE.CREATE.{stream}.{durable}", config
            )
            current = require_success(response, f"criação do consumer {durable}").get("config", {})
        else:
            current = require_success(info, f"info do consumer {durable}").get("config", {})
        compare_fields(
            current,
            config,
            ("durable_name", "deliver_subject", "deliver_group", "filter_subject", "filter_subjects", "ack_policy", "ack_wait", "max_deliver", "max_ack_pending", "replay_policy"),
            f"consumer {durable}",
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--password-file", type=Path, required=True)
    parser.add_argument("--ca-file", type=Path, required=True)
    parser.add_argument("--server-name", required=True)
    parser.add_argument("--streams", type=Path, required=True)
    parser.add_argument("--consumers", type=Path, required=True)
    parser.add_argument("--incarnation", required=True)
    parser.add_argument("--verify-only", action="store_true")
    arguments = parser.parse_args()
    if arguments.user != "blindou-core":
        fail("identidade administrativa NATS divergente")
    host, separator, port_text = arguments.endpoint.partition(":")
    if not separator or not re.fullmatch(r"[0-9]{1,5}", port_text):
        fail("endpoint NATS inválido")
    credential_value = arguments.password_file.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"[0-9a-f]{64}", credential_value):
        fail("arquivo de senha NATS inválido")
    connection = NatsConnection(
        host,
        int(port_text),
        arguments.user,
        credential_value,
        arguments.ca_file,
        arguments.server_name,
    )
    try:
        provision(
            connection,
            arguments.streams,
            arguments.consumers,
            arguments.incarnation,
            arguments.verify_only,
        )
    finally:
        credential_value = ""
        connection.close()
    mode = "verify" if arguments.verify_only else "reconcile"
    print(f"blindou_dispatch_v3_jetstream=passed mode={mode} streams=5 consumers=4")


if __name__ == "__main__":
    main()
