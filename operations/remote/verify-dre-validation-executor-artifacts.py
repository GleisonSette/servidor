#!/usr/bin/env python3
"""Valida o bootstrap fechado do executor rootless e descartável do DRE."""

from __future__ import annotations

import pathlib
import re


ROOT = pathlib.Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise SystemExit(f"[verify-dre-validation-executor-artifacts] ERRO: {message}")


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file() or path.is_symlink():
        fail(f"arquivo ausente ou simbólico: {relative}")
    return path.read_text(encoding="utf-8")


bootstrap = read("operations/remote/bootstrap-dre-validation-executor.sh")
for invariant in (
    "set -Eeuo pipefail",
    "bootstrap-dre-validation-executor.sh <commit> <archive-sha256>",
    "ubuntu && \"${VERSION_ID:-}\" == 24.04",
    "podman=4.9.3+ds1-1ubuntu0.2",
    "uidmap=1:4.13+dfsg1-4ubuntu3.2",
    "podman-compose=1.0.6-1",
    "slirp4netns=1.2.1-1build2",
    "fuse-overlayfs=1.13-1",
    "passt=0.0~git20240220.1e6f92b-1",
    "apt-get --simulate --no-remove --no-upgrade",
    "apt-get install --yes --no-remove --no-upgrade",
    "dre_validation_executor_bootstrap_stage=%s",
    "stage k3s-boundary",
    "stage apt-simulation",
    "stage packages-installed",
    "stage daemon-postcondition",
    "stage receipt",
    "rollback_new_packages",
    "comm -13 \"$packages_before\" \"$packages_after\"",
    "apiadmin:100000:65536",
    "runuser -u apiadmin -- test ! -r /etc/rancher/k3s/k3s.yaml",
    "runuser -u apiadmin -- test ! -r /run/k3s/containerd/containerd.sock",
    "podman.socket",
    "podman-auto-update.timer",
    "podman-restart.service",
    "persistent_daemon\": False",
    "k3s_access_granted\": False",
    "/var/lib/servidor-local/dre-validation-executor",
    "rm -rf --one-file-system -- \"$work_directory\"",
):
    if invariant not in bootstrap:
        fail(f"invariante do bootstrap ausente: {invariant}")
for forbidden in (
    "systemctl enable",
    "systemctl start",
    "usermod",
    "groupadd",
    "chmod 0666",
    "chmod 0777",
    "kubectl",
    "k3s kubectl",
    "docker.service",
):
    if forbidden in bootstrap:
        fail(f"operação proibida no bootstrap: {forbidden}")

package_lines = re.findall(r"^  '([^']+)'$", bootstrap, flags=re.MULTILINE)
if package_lines[:6] != [
    "podman=4.9.3+ds1-1ubuntu0.2",
    "uidmap=1:4.13+dfsg1-4ubuntu3.2",
    "podman-compose=1.0.6-1",
    "slirp4netns=1.2.1-1build2",
    "fuse-overlayfs=1.13-1",
    "passt=0.0~git20240220.1e6f92b-1",
]:
    fail("inventário ou ordem dos pacotes autorizados diverge")

helper = read("operations/Dre.SudoBootstrap.psm1")
for invariant in (
    "Invoke-DreValidationExecutorSudoBootstrap",
    "dre-validation-executor-bootstrap-",
    "/var/lib/servidor-local/bootstrap-releases/dre-validation-executor",
    "bootstrap-dre-validation-executor.sh",
    "verify-dre-validation-executor-artifacts.py",
    "sudo -S -p '' -- /bin/bash -c",
    "C:\\github\\servidor\\.env",
):
    if invariant not in helper:
        fail(f"proteção do helper sudo ausente: {invariant}")

orchestrator = read("operations/Invoke-DreValidationExecutorBootstrap.ps1")
for invariant in (
    "apiadmin@192.168.100.59",
    "git.exe",
    "archive",
    "StrictHostKeyChecking=yes",
    "Invoke-DreValidationExecutorSudoBootstrap",
    "podman-compose --version",
    "system reset --force",
    "test ! -r /etc/rancher/k3s/k3s.yaml",
    "test ! -r /run/k3s/containerd/containerd.sock",
    "dre_validation_executor_smoke=passed",
):
    if invariant not in orchestrator:
        fail(f"invariante do orquestrador ausente: {invariant}")
for forbidden in ("KUBECONFIG=", "kubectl", "k3s kubectl", "docker.sock"):
    if forbidden in orchestrator:
        fail(f"atalho proibido no orquestrador: {forbidden}")

runbook = read("runbooks/dre-validation-executor.md")
for invariant in (
    "rootless",
    "sem daemon",
    "sem acesso ao K3s",
    "make release-check",
    "make e2e",
    "rollback",
):
    if invariant not in runbook:
        fail(f"runbook incompleto: {invariant}")

print("dre_validation_executor_artifacts=passed")
