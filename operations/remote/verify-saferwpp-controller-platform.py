#!/usr/bin/env python3
"""Valida offline a materialização host-side dos controladores SaferWPP."""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise SystemExit(f"[verify-saferwpp-controller-platform] ERRO: {message}")


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file() or path.is_symlink():
        fail(f"arquivo ausente ou simbólico: {relative}")
    return path.read_text(encoding="utf-8")


def yaml_documents(relative: str) -> list[dict]:
    documents = [document for document in yaml.safe_load_all(read(relative)) if document]
    if not documents or not all(isinstance(document, dict) for document in documents):
        fail(f"YAML vazio ou inválido: {relative}")
    return documents


bootstrap = read("operations/remote/bootstrap-saferwpp-controllers.sh")
identity_controller = read("operations/remote/saferwpp-kube-identityctl")
service = read("operations/remote/saferwpp-kube-identities.service")
timer = read("operations/remote/saferwpp-kube-identities.timer")
verifier = read("operations/remote/verify-saferwpp-controller-release.py")
tests = read("operations/remote/test-saferwpp-controller-platform.py")
runbook = read("runbooks/saferwpp-controllers.md")

for invariant in (
    "/usr/local/sbin/apiwpp-deployctl verify",
    "/usr/local/sbin/blindou-deployctl verify",
    "/usr/local/sbin/secondary-slotctl verify",
    "verify-saferwpp-controller-release.py",
    "saferwpp-kube-identityctl ensure",
    "saferwpp-kube-identityctl verify",
    "visudo -cf",
    "promtool check config",
    "rollback_bootstrap",
):
    if invariant not in bootstrap:
        fail(f"invariante ausente no bootstrap: {invariant}")
for forbidden in ("sudo -S", "KEY_SERVIDOR", "system:masters", "kubectl *"):
    if forbidden in bootstrap:
        fail(f"atalho proibido no bootstrap: {forbidden}")

for invariant in (
    "IDENTITIES=('saferwpp-deployctl' 'saferwpp-secretsctl')",
    "RENEW_BEFORE_SECONDS=3888000",
    "MINIMUM_CA_VALIDITY_SECONDS=31622400",
    "extendedKeyUsage=clientAuth",
    "auth whoami",
    "https://127.0.0.1:6443",
    "client-key-data",
    "restore_renewed_identities",
):
    if invariant not in identity_controller:
        fail(f"invariante ausente nas identidades: {invariant}")
for forbidden in ("system:masters", "apiwpp-deployctl", "blindou-deployctl"):
    if forbidden in identity_controller:
        fail(f"identidade contém acoplamento proibido: {forbidden}")

for invariant in (
    "ProtectSystem=strict",
    "PrivateDevices=true",
    "NoNewPrivileges=true",
    "MemoryDenyWriteExecute=true",
    "ReadWritePaths=/etc/rancher/k3s /var/lib/prometheus/node-exporter",
):
    if invariant not in service:
        fail(f"hardening systemd ausente: {invariant}")
for invariant in ("OnCalendar=*-*-* 03:17:00", "Persistent=true"):
    if invariant not in timer:
        fail(f"agendamento de renovação ausente: {invariant}")

alerts = yaml_documents("platform/saferwpp/monitoring/controller-alerts.yaml")
alert_names = {
    rule["alert"]
    for group in alerts[0]["groups"]
    for rule in group["rules"]
}
if alert_names != {
    "SaferWppKubeIdentityCertificateExpiring",
    "SaferWppKubeIdentityReconciliationStale",
}:
    fail("inventário de alertas dos controladores diverge")
alert_expressions = "\n".join(
    str(rule["expr"])
    for group in alerts[0]["groups"]
    for rule in group["rules"]
)
for metric in (
    "saferwpp_kube_identity_certificate_expiry_timestamp_seconds",
    "saferwpp_kube_identity_last_success_timestamp_seconds",
    "absent(",
):
    if metric not in alert_expressions:
        fail(f"alertas não observam {metric}")

for relative, source in (
    ("operations/remote/verify-saferwpp-controller-release.py", verifier),
    ("operations/remote/test-saferwpp-controller-platform.py", tests),
):
    compile(source, relative, "exec")

test_result = subprocess.run(
    [sys.executable, str(ROOT / "operations/remote/test-saferwpp-controller-platform.py")],
    cwd=ROOT,
    check=False,
    capture_output=True,
    text=True,
    encoding="utf-8",
    timeout=60,
)
if test_result.returncode != 0:
    fail(f"testes offline falharam: {test_result.stderr.strip()}")

secret_pattern = re.compile(
    r"BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY|"
    r"(?i:(?:password|token|secret|private[_-]?key)\s*[:=]\s*['\"]?[A-Za-z0-9+_.-][A-Za-z0-9/+_.-]{11,})"
)
for relative in (
    "operations/remote/bootstrap-saferwpp-controllers.sh",
    "operations/remote/saferwpp-kube-identityctl",
    "operations/remote/saferwpp-kube-identities.service",
    "operations/remote/saferwpp-kube-identities.timer",
    "operations/remote/verify-saferwpp-controller-release.py",
    "operations/remote/test-saferwpp-controller-platform.py",
    "platform/saferwpp/monitoring/controller-alerts.yaml",
    "runbooks/saferwpp-controllers.md",
):
    if secret_pattern.search(read(relative)):
        fail(f"possível segredo encontrado em {relative}")

print("saferwpp_controller_platform_artifacts=passed")
