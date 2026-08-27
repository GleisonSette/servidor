#!/usr/bin/env python3
"""Testes offline da cadeia de materialização dos controladores SaferWPP."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
VERIFIER_PATH = ROOT / "operations/remote/verify-saferwpp-controller-release.py"
SPEC = importlib.util.spec_from_file_location("saferwpp_controller_verifier", VERIFIER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("não foi possível carregar o verificador")
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)


class ControllerReleaseVerifierTests(unittest.TestCase):
    def test_paths_inseguros_sao_recusados(self) -> None:
        for value in ("", "/absolute", "../escape", "a/../b", "a\\b", "./a"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                VERIFIER.safe_member_name(value)

    def test_archive_recusa_link_simbolico(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            archive_path = Path(name) / "unsafe.tar.gz"
            with tarfile.open(archive_path, mode="w:gz") as archive:
                member = tarfile.TarInfo("payload/bin/saferwpp-deployctl")
                member.type = tarfile.SYMTYPE
                member.linkname = "/bin/sh"
                archive.addfile(member)
            with self.assertRaisesRegex(ValueError, "tipo de membro recusado"):
                VERIFIER.load_archive(archive_path)

    def test_scan_recusa_vulnerabilidade_e_segredo(self) -> None:
        for key in ("Vulnerabilities", "Secrets"):
            payload = {"Results": [{key: [{"finding": "sanitized"}]}]}
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "finding"):
                VERIFIER.verify_scan(json.dumps(payload).encode("utf-8"))

    def test_extracao_preserva_inventario_e_modos(self) -> None:
        contents = {
            relative: f"content:{relative}".encode("utf-8")
            for relative in set(VERIFIER.LAYOUT) | set(VERIFIER.METADATA)
        }
        with tempfile.TemporaryDirectory() as name:
            destination = Path(name) / "release"
            VERIFIER.extract_contents(contents, destination)
            extracted = {
                path.relative_to(destination).as_posix()
                for path in destination.rglob("*")
                if path.is_file()
            }
            self.assertEqual(extracted, set(contents))
            if os.name != "nt":
                for relative, expected_mode in VERIFIER.LAYOUT.items():
                    self.assertEqual(
                        (destination / relative).stat().st_mode & 0o777,
                        expected_mode,
                    )


class PlatformContractTests(unittest.TestCase):
    def test_bootstrap_mantem_fronteiras_fechadas(self) -> None:
        bootstrap = (ROOT / "operations/remote/bootstrap-saferwpp-controllers.sh").read_text(
            encoding="utf-8"
        )
        for invariant in (
            "/usr/local/sbin/apiwpp-deployctl verify",
            "/usr/local/sbin/blindou-deployctl verify",
            "/usr/local/sbin/secondary-slotctl verify",
            "verify-saferwpp-controller-release.py",
            "saferwpp-kube-identityctl ensure",
            "saferwpp-kube-identityctl verify",
            "visudo -cf",
            "promtool check config",
        ):
            self.assertIn(invariant, bootstrap)
        self.assertNotIn("kubectl apply -f $", bootstrap)
        self.assertNotIn("sudo -S", bootstrap)

    def test_identidades_sao_exclusivas_e_renovaveis(self) -> None:
        controller = (ROOT / "operations/remote/saferwpp-kube-identityctl").read_text(
            encoding="utf-8"
        )
        for identity in ("saferwpp-deployctl", "saferwpp-secretsctl"):
            self.assertIn(identity, controller)
        for invariant in (
            "RENEW_BEFORE_SECONDS=3888000",
            "MINIMUM_CA_VALIDITY_SECONDS=31622400",
            "extendedKeyUsage=clientAuth",
            "auth whoami",
            "https://127.0.0.1:6443",
            "client-key-data",
        ):
            self.assertIn(invariant, controller)
        for forbidden in ("system:masters", "apiwpp-deployctl", "blindou-deployctl"):
            self.assertNotIn(forbidden, controller)


if __name__ == "__main__":
    unittest.main()
