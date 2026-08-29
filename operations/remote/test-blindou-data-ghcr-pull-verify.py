#!/usr/bin/env python3
"""Testes do pull PostgreSQL dedicado, sem rede ou segredo."""

from __future__ import annotations

import email.message
import importlib.util
import unittest
import urllib.request
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("blindou-data-ghcr-pull-verify.py")
SPEC = importlib.util.spec_from_file_location("blindou_data_ghcr_pull_verify", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise SystemExit("não foi possível carregar o verificador GHCR")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PullVerifierTests(unittest.TestCase):
    def test_selects_exactly_one_linux_amd64_manifest(self) -> None:
        selected = "sha256:" + "a" * 64
        document = {
            "mediaType": "application/vnd.oci.image.index.v1+json",
            "manifests": [
                {
                    "digest": selected,
                    "platform": {"os": "linux", "architecture": "amd64"},
                },
                {
                    "digest": "sha256:" + "b" * 64,
                    "platform": {"os": "unknown", "architecture": "unknown"},
                },
            ],
        }
        self.assertEqual(MODULE.select_linux_amd64_manifest(document), selected)

    def test_rejects_ambiguous_linux_amd64_index(self) -> None:
        document = {
            "mediaType": "application/vnd.oci.image.index.v1+json",
            "manifests": [
                {
                    "digest": "sha256:" + value * 64,
                    "platform": {"os": "linux", "architecture": "amd64"},
                }
                for value in ("a", "b")
            ],
        }
        with self.assertRaises(SystemExit):
            MODULE.select_linux_amd64_manifest(document)

    def test_collects_unique_config_and_layer_digests(self) -> None:
        config = "sha256:" + "c" * 64
        layer = "sha256:" + "d" * 64
        document = {
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "config": {"digest": config},
            "layers": [{"digest": layer}, {"digest": layer}],
        }
        self.assertEqual(MODULE.manifest_blobs(document), [config, layer])

    def test_cross_host_redirect_removes_authorization(self) -> None:
        request = urllib.request.Request(
            "https://ghcr.io/v2/example/blobs/sha256:abc",
            headers={"Authorization": "Bearer synthetic-test-value"},
        )
        redirected = MODULE.SafeRedirectHandler().redirect_request(
            request,
            None,
            302,
            "Found",
            email.message.Message(),
            "https://pkg-containers.githubusercontent.com/blob",
        )
        self.assertIsNotNone(redirected)
        self.assertIsNone(redirected.get_header("Authorization"))

    def test_image_contract_rejects_other_owners(self) -> None:
        valid = "ghcr.io/gleisonsette/blindou-postgres@sha256:" + "e" * 64
        invalid = valid.replace("gleisonsette", "other")
        self.assertIsNotNone(MODULE.IMAGE_PATTERN.fullmatch(valid))
        self.assertIsNone(MODULE.IMAGE_PATTERN.fullmatch(invalid))

    def test_image_contract_accepts_only_postgres(self) -> None:
        valid = "ghcr.io/gleisonsette/blindou-postgres@sha256:" + "f" * 64
        match = MODULE.IMAGE_PATTERN.fullmatch(valid)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "sha256:" + "f" * 64)
        self.assertIsNone(
            MODULE.IMAGE_PATTERN.fullmatch(
                "ghcr.io/gleisonsette/blindou-backend@sha256:" + "f" * 64
            )
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
