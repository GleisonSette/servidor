#!/usr/bin/env python3
"""Testes determinísticos do reconciliador JetStream sem abrir rede."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import Any


SOURCE = Path(__file__).with_name("blindou-dispatch-v3-jetstream.py")
SPEC = importlib.util.spec_from_file_location("blindou_dispatch_v3_jetstream", SOURCE)
if SPEC is None or SPEC.loader is None:
    raise SystemExit("não foi possível carregar o provisionador JetStream")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

INCARNATION = "8ea56bb5-e428-4d51-9d12-a4ea4ae0c599"


def fixtures() -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    streams: list[dict[str, Any]] = []
    for name in MODULE.EXPECTED_STREAM_ORDER:
        streams.append(
            {
                "name": name,
                "subjects": [f"blindou.test.{name.lower()}"],
                "retention": "limits",
                "discard": "new",
                "max_age": 10,
                "max_bytes": 20,
                "max_msg_size": 30,
                "duplicate_window": 40,
                "storage": "file",
                "num_replicas": 1,
                "metadata": {
                    "blindou.stream_incarnation": "__STREAM_INCARNATION_UUID__"
                },
            }
        )
    streams[0]["discard"] = "old"
    streams[0]["allow_msg_schedules"] = True
    streams[1]["sources"] = [
        {
            "name": MODULE.EXPECTED_STREAM_ORDER[0],
            "subject_transforms": [{"src": "source.*", "dest": "target.{{wildcard(1)}}"}],
        }
    ]
    consumers = [
        {
            "stream": MODULE.EXPECTED_STREAM_ORDER[index % len(MODULE.EXPECTED_STREAM_ORDER)],
            "config": {
                "durable_name": durable,
                "deliver_subject": f"_INBOX.{durable}",
                "deliver_group": durable,
                "filter_subject": f"blindou.test.{index}",
                "ack_policy": "explicit",
                "ack_wait": 10,
                "max_deliver": 20,
                "max_ack_pending": 30,
                "replay_policy": "instant",
            },
        }
        for index, durable in enumerate(sorted(MODULE.EXPECTED_CONSUMERS))
    ]
    return streams, consumers


class FakeConnection:
    def __init__(self, *, existing: bool, drift_sources: bool = False) -> None:
        self.existing = existing
        self.drift_sources = drift_sources
        self.configs: dict[str, dict[str, Any]] = {}

    def request(
        self, subject: str, body: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        if ".INFO." in subject:
            suffix = subject.split(".INFO.", 1)[1]
            key = suffix.rsplit(".", 1)[-1] if ".CONSUMER.INFO." in subject else suffix
            if not self.existing and key not in self.configs:
                return {"error": {"code": 404, "description": "not found"}}
            config = json.loads(json.dumps(self.configs[key]))
            if self.drift_sources and key == MODULE.EXPECTED_STREAM_ORDER[1]:
                config.pop("sources", None)
            return {"config": config}
        if body is None:
            raise AssertionError(f"payload ausente em {subject}")
        key = body.get("name") or body.get("durable_name")
        if not isinstance(key, str):
            raise AssertionError(f"identidade ausente em {subject}")
        self.configs[key] = json.loads(json.dumps(body))
        return {"config": json.loads(json.dumps(body))}


def run() -> None:
    streams, consumers = fixtures()
    original_load_json = MODULE.load_json
    MODULE.load_json = lambda path: streams if path.name == "streams.json" else consumers
    try:
        connection = FakeConnection(existing=False)
        MODULE.provision(
            connection,
            Path("streams.json"),
            Path("consumers.json"),
            INCARNATION,
            False,
        )
        if len(connection.configs) != 9:
            raise AssertionError("reconciliação não criou cinco streams e quatro consumers")
        connection.existing = True
        MODULE.provision(
            connection,
            Path("streams.json"),
            Path("consumers.json"),
            INCARNATION,
            True,
        )
        connection.drift_sources = True
        try:
            MODULE.provision(
                connection,
                Path("streams.json"),
                Path("consumers.json"),
                INCARNATION,
                True,
            )
        except SystemExit as error:
            if "sources" not in str(error):
                raise AssertionError("drift de source falhou sem diagnóstico fechado") from error
        else:
            raise AssertionError("modo somente leitura aceitou drift de source")
    finally:
        MODULE.load_json = original_load_json
    print("blindou_dispatch_v3_jetstream_tests=passed")


if __name__ == "__main__":
    run()
