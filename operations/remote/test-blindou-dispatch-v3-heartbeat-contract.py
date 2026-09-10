#!/usr/bin/env python3
"""Regressões offline da transição assinada D085; não acessa host ou banco."""
from copy import deepcopy
from pathlib import Path
import runpy
import tempfile
import unittest

import yaml

CONTRACT = runpy.run_path(str(Path(__file__).with_name("blindou-release-verify.py")))
OLD_SHA, NEW_SHA = "1" * 40, "2" * 40
OLD_BACKEND, NEW_BACKEND = (f"ghcr.io/gleisonsette/blindou-backend@sha256:{c * 64}" for c in "ab")
OLD_CDC, NEW_CDC = (f"ghcr.io/gleisonsette/blindou-debezium@sha256:{c * 64}" for c in "cd")


def fixtures():
    properties = {
        "debezium.source.table.include.list": "public.dispatch_outbox_v3",
        "debezium.source.heartbeat.interval.ms": "0",
        "debezium.transforms": "outbox,dropNullScheduleHeaders",
        "debezium.source.slot.name": "blindou_dispatch_v3_outbox_slot",
        "debezium.source.offset.flush.interval.ms": "0",
        "debezium.source.database.sslmode": "verify-full",
        "debezium.sink.nats-jetstream.async.timeout.ms": "5000",
    }

    def config(values):
        return "\n".join(f"{key}={value}" for key, value in values.items()) + "\n"

    def workload(kind, name, image):
        return {"kind": kind, "metadata": {"name": name, "namespace": "blindou-production"},
                "spec": {"replicas": 1, "template": {
                    "metadata": {"annotations": {"blindou.io/release": OLD_SHA}},
                    "spec": {"containers": [{"name": name, "image": image,
                        "securityContext": {"allowPrivilegeEscalation": False},
                        "env": [{"name": "APP_RELEASE_ID", "value": OLD_SHA}]}]}}}}

    old = [{"kind": "ConfigMap", "metadata": {"name": "blindou-debezium-v3-config",
                "namespace": "blindou-production"}, "data": {"application.properties": config(properties)}},
           workload("Deployment", "blindou-backend", OLD_BACKEND),
           workload("StatefulSet", "blindou-debezium-v3", OLD_CDC),
           workload("Job", f"blindou-migrate-{OLD_SHA[:12]}", OLD_BACKEND),
           workload("StatefulSet", "blindou-nats", "ghcr.io/gleisonsette/blindou-nats@sha256:" + "e" * 64)]
    new = deepcopy(old)
    new[0]["data"]["application.properties"] = config({**properties, **CONTRACT["HEARTBEAT_PROPERTIES"]})
    for document in new[1:]:
        if document["kind"] == "Job":
            document["metadata"]["name"] = f"blindou-migrate-{NEW_SHA[:12]}"
        template = document["spec"]["template"]
        template["metadata"]["annotations"]["blindou.io/release"] = NEW_SHA
        container = template["spec"]["containers"][0]
        container["env"][0]["value"] = NEW_SHA
        container["image"] = {OLD_BACKEND: NEW_BACKEND, OLD_CDC: NEW_CDC}.get(container["image"], container["image"])
    return old, new


class HeartbeatTransitionTests(unittest.TestCase):
    def verify(self, old, new):
        CONTRACT["validate_heartbeat_transition"](old, new, OLD_SHA, NEW_SHA,
                                                   OLD_BACKEND, NEW_BACKEND, OLD_CDC, NEW_CDC)

    def test_exact_transition_preserves_inputs(self):
        old, new = fixtures()
        snapshot = deepcopy((old, new))
        self.verify(old, new)
        self.assertEqual(snapshot, (old, new))

    def test_each_required_heartbeat_property_is_mandatory(self):
        for key in CONTRACT["HEARTBEAT_PROPERTIES"]:
            with self.subTest(key=key):
                old, new = fixtures()
                new[0]["data"]["application.properties"] = "\n".join(
                    line for line in new[0]["data"]["application.properties"].splitlines()
                    if not line.startswith(key + "="))
                with self.assertRaises(SystemExit):
                    self.verify(old, new)

    def test_no_tls_slot_offset_or_puback_changes(self):
        for key in ("debezium.source.database.sslmode", "debezium.source.slot.name",
                    "debezium.source.offset.flush.interval.ms", "debezium.sink.nats-jetstream.async.timeout.ms"):
            with self.subTest(key=key):
                old, new = fixtures()
                text = new[0]["data"]["application.properties"]
                new[0]["data"]["application.properties"] = "\n".join(
                    key + "=invalid" if line.startswith(key + "=") else line for line in text.splitlines())
                with self.assertRaises(SystemExit):
                    self.verify(old, new)

    def test_manifest_drift_is_refused(self):
        mutations = [
            lambda docs: docs[1]["spec"].update(replicas=2),
            lambda docs: docs[1]["spec"]["template"]["spec"].update(hostNetwork=True),
            lambda docs: docs[1]["spec"]["template"]["spec"]["containers"][0]["securityContext"].update(allowPrivilegeEscalation=True),
            lambda docs: docs[4]["spec"]["template"]["spec"]["containers"][0].update(image=NEW_BACKEND),
            lambda docs: docs[0]["data"].update(unexpected="value"),
            lambda docs: docs.append(deepcopy(docs[0])),
            lambda docs: docs.pop(),
            lambda docs: docs[1]["spec"]["template"]["metadata"]["annotations"].update({"blindou.io/release": OLD_SHA}),
        ]
        for number, mutation in enumerate(mutations):
            with self.subTest(number=number):
                old, new = fixtures()
                mutation(new)
                with self.assertRaises(SystemExit):
                    self.verify(old, new)

    def test_duplicate_properties_are_refused(self):
        old, new = fixtures()
        new[0]["data"]["application.properties"] += "debezium.source.heartbeat.interval.ms=60000\n"
        with self.assertRaises(SystemExit):
            self.verify(old, new)

    def test_partial_baseline_is_refused(self):
        old, new = fixtures()
        old[0]["data"]["application.properties"] += "debezium.source.lsn.flush.mode=connector\n"
        with self.assertRaises(SystemExit):
            self.verify(old, new)

    def test_bundle_preserves_streams_and_consumers(self):
        old, new = fixtures()
        with tempfile.TemporaryDirectory(prefix="blindou-d085-contract-") as temporary:
            directories = [Path(temporary) / name for name in ("previous", "candidate")]
            for directory, documents in zip(directories, (old, new)):
                files = CONTRACT["REQUIRED_FILES"] | {f"workers/synthetic-{number}.yaml" for number in range(16)}
                for name in files:
                    path = directory / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("[]" if name.endswith(".json") else "", encoding="utf-8")
                (directory / "70-dispatch-v3-foundation.yaml").write_text(
                    yaml.safe_dump_all(documents), encoding="utf-8")

            def verify():
                CONTRACT["validate_heartbeat_bundles"](*directories, OLD_SHA, NEW_SHA,
                    OLD_BACKEND, NEW_BACKEND, OLD_CDC, NEW_CDC)
            verify()
            for name in ("dispatch-v3/streams.json", "dispatch-v3/consumers.json"):
                with self.subTest(name=name):
                    path = directories[1] / name
                    path.write_text('[{"changed":true}]', encoding="utf-8")
                    with self.assertRaises(SystemExit):
                        verify()
                    path.write_text("[]", encoding="utf-8")
            (directories[1] / "unexpected.yaml").write_text("", encoding="utf-8")
            with self.assertRaises(SystemExit):
                verify()

    def test_same_images_or_release_are_refused(self):
        old, new = fixtures()
        for release, backend, cdc in ((OLD_SHA, NEW_BACKEND, NEW_CDC),
                                      (NEW_SHA, OLD_BACKEND, NEW_CDC),
                                      (NEW_SHA, NEW_BACKEND, OLD_CDC)):
            with self.subTest(release=release, backend=backend, cdc=cdc):
                with self.assertRaises(SystemExit):
                    CONTRACT["validate_heartbeat_transition"](old, new, OLD_SHA, release,
                        OLD_BACKEND, backend, OLD_CDC, cdc)


if __name__ == "__main__":
    unittest.main()
