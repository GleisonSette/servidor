#!/usr/bin/env python3
"""Testes unitários das regras puras do slot compartilhado."""

from __future__ import annotations

import pathlib
import stat
import sys
import unittest
from types import SimpleNamespace


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from secondary_slot import (  # noqa: E402
    ContractError,
    RuntimeObservation,
    SlotState,
    activated_workload_counts,
    active_workloads_are_healthy,
    count_active_workloads,
    long_running_workload_is_active,
    parse_state,
    runtime_is_fully_suspended,
    state_matches_runtime,
    state_from_unambiguous_runtime,
    textfile_directory_metadata_is_safe,
    workload_is_active,
)


VALID_STATE = """schema=1
slot=secondary
generation=7
active_occupant=apiwpp
apiwpp_workloads=1
saferwpp_workloads=0
updated_at=2026-08-26T12:00:00-03:00
"""


class StateContractTests(unittest.TestCase):
    def test_exact_state_round_trip(self) -> None:
        state = parse_state(VALID_STATE)
        self.assertEqual(state.generation, 7)
        self.assertEqual(state.serialize(), VALID_STATE)

    def test_extra_or_reordered_field_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            parse_state(VALID_STATE + "unexpected=true\n")
        with self.assertRaises(ContractError):
            parse_state(VALID_STATE.replace("slot=secondary\n", ""))

    def test_cross_member_count_is_rejected(self) -> None:
        with self.assertRaises(ContractError):
            SlotState(1, "apiwpp", 1, 1, "2026-08-26T15:00:00+00:00").validate()
        with self.assertRaises(ContractError):
            SlotState(1, "none", 1, 0, "2026-08-26T15:00:00+00:00").validate()

    def test_runtime_reservation_and_active_state(self) -> None:
        reserved = SlotState(2, "apiwpp", 0, 0, "2026-08-26T15:00:00+00:00")
        suspended = RuntimeObservation("suspended", 0, 0, True, False)
        self.assertTrue(state_matches_runtime(reserved, suspended))
        active = SlotState(3, "apiwpp", 1, 0, "2026-08-26T15:00:00+00:00")
        self.assertTrue(
            state_matches_runtime(active, RuntimeObservation("active", 1, 0, True, False))
        )

    def test_split_brain_has_no_unambiguous_occupant(self) -> None:
        runtime = RuntimeObservation("active", 1, 2, True, True)
        self.assertTrue(runtime.split_brain)
        self.assertIsNone(runtime.unambiguous_occupant)

    def test_reconciliation_accepts_only_unambiguous_runtime(self) -> None:
        self.assertEqual(
            RuntimeObservation("active", 1, 0, True, False).unambiguous_occupant,
            "apiwpp",
        )
        self.assertEqual(
            RuntimeObservation("suspended", 0, 3, True, True).unambiguous_occupant,
            "saferwpp",
        )
        self.assertEqual(
            RuntimeObservation("suspended", 0, 0, True, False).unambiguous_occupant,
            "none",
        )
        self.assertIsNone(
            RuntimeObservation("suspended", 0, 3, False, True).unambiguous_occupant
        )
        self.assertIsNone(
            RuntimeObservation("suspended", 0, 3, True, False).unambiguous_occupant
        )

    def test_state_machine_derives_only_safe_states(self) -> None:
        suspended = RuntimeObservation("suspended", 0, 0, True, False)
        self.assertTrue(runtime_is_fully_suspended(suspended))
        reconciled = state_from_unambiguous_runtime(
            9, suspended, "2026-08-26T15:00:00+00:00"
        )
        self.assertEqual(reconciled.active_occupant, "none")
        safer = RuntimeObservation("suspended", 0, 6, True, True)
        self.assertEqual(activated_workload_counts("saferwpp", safer), (0, 6))
        with self.assertRaises(ContractError):
            activated_workload_counts(
                "saferwpp", RuntimeObservation("suspended", 0, 1, True, False)
            )


class WorkloadClassificationTests(unittest.TestCase):
    def test_completed_job_does_not_keep_slot_active(self) -> None:
        job = {
            "kind": "Job",
            "spec": {},
            "status": {"conditions": [{"type": "Complete", "status": "True"}]},
        }
        self.assertFalse(workload_is_active(job))

    def test_suspended_job_and_cronjob_are_inactive(self) -> None:
        items = [
            {"kind": "Job", "spec": {"suspend": True}, "status": {}},
            {"kind": "CronJob", "spec": {"suspend": True}, "status": {}},
        ]
        self.assertEqual(count_active_workloads(items), 0)

    def test_replica_set_owned_by_deployment_is_not_counted_twice(self) -> None:
        replica_set = {
            "kind": "ReplicaSet",
            "metadata": {"ownerReferences": [{"kind": "Deployment", "name": "app"}]},
            "spec": {"replicas": 1},
            "status": {"readyReplicas": 1},
        }
        self.assertEqual(count_active_workloads([replica_set]), 0)

    def test_ready_deployment_is_active_and_healthy(self) -> None:
        deployment = {
            "kind": "Deployment",
            "metadata": {"generation": 4},
            "spec": {"replicas": 1},
            "status": {
                "observedGeneration": 4,
                "updatedReplicas": 1,
                "availableReplicas": 1,
                "readyReplicas": 1,
            },
        }
        self.assertEqual(count_active_workloads([deployment]), 1)
        self.assertTrue(active_workloads_are_healthy([deployment]))

    def test_unready_deployment_is_not_healthy(self) -> None:
        deployment = {
            "kind": "Deployment",
            "metadata": {"generation": 2},
            "spec": {"replicas": 1},
            "status": {"observedGeneration": 2, "readyReplicas": 0},
        }
        self.assertFalse(active_workloads_are_healthy([deployment]))

    def test_job_does_not_replace_continuous_runtime(self) -> None:
        job = {"kind": "Job", "spec": {}, "status": {"active": 1}}
        self.assertTrue(workload_is_active(job))
        self.assertFalse(long_running_workload_is_active(job))


class TextfileCollectorDirectoryTests(unittest.TestCase):
    def test_root_and_prometheus_ownership_are_accepted(self) -> None:
        for uid, gid in ((0, 0), (112, 118)):
            metadata = SimpleNamespace(
                st_mode=stat.S_IFDIR | 0o755,
                st_uid=uid,
                st_gid=gid,
            )
            self.assertTrue(textfile_directory_metadata_is_safe(metadata, 112, 118))

    def test_writable_or_unexpected_owner_is_rejected(self) -> None:
        for mode, uid, gid in ((0o775, 112, 118), (0o755, 1000, 1000)):
            metadata = SimpleNamespace(
                st_mode=stat.S_IFDIR | mode,
                st_uid=uid,
                st_gid=gid,
            )
            self.assertFalse(textfile_directory_metadata_is_safe(metadata, 112, 118))


if __name__ == "__main__":
    unittest.main()
