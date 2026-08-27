#!/usr/bin/env python3
"""Primitivas seguras do slot alternável APIWPP/SaferWPP."""

from __future__ import annotations

import base64
import binascii
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import stat
import subprocess
import tempfile
from dataclasses import dataclass
from typing import Any, Iterable, Sequence


STATE_KEYS = (
    "schema",
    "slot",
    "generation",
    "active_occupant",
    "apiwpp_workloads",
    "saferwpp_workloads",
    "updated_at",
)
OCCUPANTS = frozenset({"apiwpp", "saferwpp", "none"})
OPERATION_PATTERN = re.compile(r"^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
RELEASE_PATTERN = re.compile(r"^[0-9a-f]{40}$")
COMMAND_TIMEOUT_SECONDS = 120
JSONL_MAX_BYTES = 16 * 1024 * 1024
JSONL_ROTATIONS = 5
STATE_HISTORY_MAX_FILES = 256

API_NAMESPACE = "apiwpp"
API_DEPLOYMENT = "apiwpp"
API_RUNTIME_SELECTOR = (
    "app.kubernetes.io/name=apiwpp,app.kubernetes.io/component=runtime"
)
SAFER_NAMESPACES = (
    "saferwpp-lab",
    "saferdock-identity",
    "saferdock-platform",
)
BLINDOU_NAMESPACES = ("blindou-production", "blindou-edge")

MEMBER_LABEL = "platform.servidor.local/secondary-slot-member"
STATE_LABEL = "platform.servidor.local/secondary-slot-state"
GENERATION_ANNOTATION = "platform.servidor.local/secondary-slot-generation"

WORKLOAD_RESOURCES = (
    "deployment,statefulset,daemonset,replicaset,replicationcontroller,job,cronjob,pod"
)
BLINDOU_FINGERPRINT_RESOURCES = (
    "deployment,statefulset,daemonset,replicaset,replicationcontroller,job,cronjob,service,configmap,secret,"
    "persistentvolumeclaim,networkpolicy,resourcequota,limitrange,serviceaccount"
)


def textfile_directory_metadata_is_safe(
    metadata: os.stat_result,
    prometheus_uid: int,
    prometheus_gid: int,
) -> bool:
    """Aceita somente o diretório padrão imutável por grupo/outros."""

    ownership = (metadata.st_uid, metadata.st_gid)
    return (
        stat.S_ISDIR(metadata.st_mode)
        and stat.S_IMODE(metadata.st_mode) == 0o755
        and ownership in {(0, 0), (prometheus_uid, prometheus_gid)}
    )


class ContractError(RuntimeError):
    """Indica que um invariante operacional falhou de forma fechada."""


@dataclass(frozen=True)
class SlotState:
    generation: int
    active_occupant: str
    apiwpp_workloads: int
    saferwpp_workloads: int
    updated_at: str

    def validate(self) -> None:
        if self.generation < 1:
            raise ContractError("generation deve ser positiva")
        if self.active_occupant not in OCCUPANTS:
            raise ContractError("active_occupant inválido")
        if self.apiwpp_workloads < 0 or self.saferwpp_workloads < 0:
            raise ContractError("contagem de workloads negativa")
        if self.active_occupant == "none" and (
            self.apiwpp_workloads != 0 or self.saferwpp_workloads != 0
        ):
            raise ContractError("estado none exige zero workload nos dois lados")
        if self.active_occupant == "apiwpp" and (
            self.apiwpp_workloads not in (0, 1) or self.saferwpp_workloads != 0
        ):
            raise ContractError("reserva APIWPP aceita zero ou um workload e SaferWPP zero")
        if self.active_occupant == "saferwpp" and self.apiwpp_workloads != 0:
            raise ContractError("reserva SaferWPP exige APIWPP sem workload")
        parse_timestamp(self.updated_at)

    def serialize(self) -> str:
        self.validate()
        return (
            "schema=1\n"
            "slot=secondary\n"
            f"generation={self.generation}\n"
            f"active_occupant={self.active_occupant}\n"
            f"apiwpp_workloads={self.apiwpp_workloads}\n"
            f"saferwpp_workloads={self.saferwpp_workloads}\n"
            f"updated_at={self.updated_at}\n"
        )


@dataclass(frozen=True)
class RuntimeObservation:
    apiwpp_state: str
    apiwpp_workloads: int
    saferwpp_workloads: int
    saferwpp_healthy: bool
    saferwpp_required_namespaces_active: bool

    @property
    def split_brain(self) -> bool:
        return self.apiwpp_workloads > 0 and self.saferwpp_workloads > 0

    @property
    def unambiguous_occupant(self) -> str | None:
        if self.split_brain or self.apiwpp_state == "ambiguous":
            return None
        if self.apiwpp_state == "active" and self.saferwpp_workloads == 0:
            return "apiwpp"
        if (
            self.apiwpp_state == "suspended"
            and self.saferwpp_workloads > 0
            and self.saferwpp_healthy
            and self.saferwpp_required_namespaces_active
        ):
            return "saferwpp"
        if self.apiwpp_state == "suspended" and self.saferwpp_workloads == 0:
            return "none"
        return None


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def parse_timestamp(value: str) -> dt.datetime:
    try:
        parsed = dt.datetime.fromisoformat(value)
    except ValueError as error:
        raise ContractError("updated_at não é ISO 8601") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ContractError("updated_at deve conter offset explícito")
    return parsed


def parse_exact_key_values(text: str, expected_keys: Sequence[str]) -> dict[str, str]:
    lines = text.splitlines()
    if len(lines) != len(expected_keys):
        raise ContractError("quantidade de campos divergente")
    parsed: dict[str, str] = {}
    for expected, line in zip(expected_keys, lines, strict=True):
        if "=" not in line:
            raise ContractError(f"campo {expected} não usa chave=valor")
        key, value = line.split("=", 1)
        if key != expected or not value:
            raise ContractError(f"campo esperado em ordem fixa: {expected}")
        parsed[key] = value
    return parsed


def parse_state(text: str) -> SlotState:
    fields = parse_exact_key_values(text, STATE_KEYS)
    if fields["schema"] != "1" or fields["slot"] != "secondary":
        raise ContractError("schema ou slot divergente")
    try:
        state = SlotState(
            generation=int(fields["generation"]),
            active_occupant=fields["active_occupant"],
            apiwpp_workloads=int(fields["apiwpp_workloads"]),
            saferwpp_workloads=int(fields["saferwpp_workloads"]),
            updated_at=fields["updated_at"],
        )
    except ValueError as error:
        raise ContractError("generation ou contagem não é inteira") from error
    state.validate()
    return state


def require_secure_regular_file(path: pathlib.Path, mode: int = 0o600) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise ContractError(f"arquivo obrigatório ausente: {path}") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise ContractError(f"arquivo não é regular: {path}")
    if metadata.st_nlink != 1:
        raise ContractError(f"arquivo possui hard link inesperado: {path}")
    if metadata.st_uid != 0 or metadata.st_gid != 0:
        raise ContractError(f"arquivo não pertence a root:root: {path}")
    if stat.S_IMODE(metadata.st_mode) != mode:
        raise ContractError(f"modo inseguro em {path}; esperado {mode:04o}")


def read_secure_state(path: pathlib.Path) -> SlotState:
    require_secure_regular_file(path)
    return parse_state(path.read_text(encoding="utf-8"))


def ensure_secure_directory(path: pathlib.Path, mode: int = 0o700) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=mode)
    metadata = path.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or path.is_symlink():
        raise ContractError(f"diretório inválido: {path}")
    if metadata.st_uid != 0 or metadata.st_gid != 0:
        raise ContractError(f"diretório não pertence a root:root: {path}")
    os.chmod(path, mode)


def atomic_secure_write(path: pathlib.Path, content: str, mode: int = 0o600) -> None:
    ensure_secure_directory(path.parent)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = pathlib.Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        os.fchown(descriptor, 0, 0)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            descriptor = -1
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        temporary.unlink(missing_ok=True)


def append_secure_jsonl(
    path: pathlib.Path,
    event: dict[str, Any],
    *,
    max_bytes: int = JSONL_MAX_BYTES,
    rotations: int = JSONL_ROTATIONS,
) -> None:
    ensure_secure_directory(path.parent)
    if path.exists() or path.is_symlink():
        require_secure_regular_file(path)
    payload = json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n"
    payload_bytes = payload.encode("utf-8")
    if len(payload_bytes) > max_bytes:
        raise ContractError("evento JSONL excede o limite do arquivo")
    if path.exists() and path.stat().st_size + len(payload_bytes) > max_bytes:
        oldest = pathlib.Path(f"{path}.{rotations}")
        if oldest.exists() or oldest.is_symlink():
            require_secure_regular_file(oldest)
            oldest.unlink()
        for index in range(rotations - 1, 0, -1):
            source = pathlib.Path(f"{path}.{index}")
            if source.exists() or source.is_symlink():
                require_secure_regular_file(source)
                os.replace(source, pathlib.Path(f"{path}.{index + 1}"))
        os.replace(path, pathlib.Path(f"{path}.1"))
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        os.fchown(descriptor, 0, 0)
        os.write(descriptor, payload_bytes)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    directory_descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_descriptor)
    finally:
        os.close(directory_descriptor)


def prune_secure_history(
    directory: pathlib.Path, *, max_files: int = STATE_HISTORY_MAX_FILES
) -> None:
    if max_files < 1:
        raise ContractError("retenção do histórico deve ser positiva")
    ensure_secure_directory(directory)
    entries: list[tuple[int, str, pathlib.Path]] = []
    for path in directory.iterdir():
        require_secure_regular_file(path)
        entries.append((path.stat().st_mtime_ns, path.name, path))
    for _, _, path in sorted(entries)[:-max_files]:
        path.unlink()
    directory_descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_descriptor)
    finally:
        os.close(directory_descriptor)


class CommandRunner:
    def _execute(self, arguments: Sequence[str]) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(
                list(arguments),
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=COMMAND_TIMEOUT_SECONDS,
                env={"PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"},
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ContractError(f"não foi possível executar {arguments[0]}") from error

    def run(self, arguments: Sequence[str], *, check: bool = True) -> str:
        result = self._execute(arguments)
        if check and result.returncode != 0:
            detail = (result.stderr or result.stdout).strip().splitlines()
            safe_detail = detail[-1][:300] if detail else "sem diagnóstico"
            raise ContractError(f"comando restrito falhou: {arguments[0]}: {safe_detail}")
        return result.stdout

    def succeeds(self, arguments: Sequence[str]) -> bool:
        return self._execute(arguments).returncode == 0


class Kubernetes:
    def __init__(self, runner: CommandRunner) -> None:
        self.runner = runner

    def command(self, *arguments: str, check: bool = True) -> str:
        return self.runner.run(("k3s", "kubectl", *arguments), check=check)

    def json(self, *arguments: str) -> dict[str, Any]:
        raw = self.command(*arguments, "-o", "json")
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as error:
            raise ContractError("Kubernetes retornou JSON inválido") from error
        if not isinstance(value, dict):
            raise ContractError("Kubernetes retornou contrato inesperado")
        return value

    def namespace_exists(self, namespace: str) -> bool:
        return self.runner.succeeds(
            ("k3s", "kubectl", "get", "namespace", namespace)
        )

    def namespace(self, namespace: str) -> dict[str, Any]:
        return self.json("get", "namespace", namespace)

    def namespace_workloads(self, namespace: str) -> list[dict[str, Any]]:
        document = self.json("-n", namespace, "get", WORKLOAD_RESOURCES)
        items = document.get("items")
        if not isinstance(items, list):
            raise ContractError(f"lista de workloads inválida em {namespace}")
        return [item for item in items if isinstance(item, dict)]

    def label_namespace(self, namespace: str, key: str, value: str) -> None:
        self.command("label", "namespace", namespace, f"{key}={value}", "--overwrite")

    def annotate_namespace(self, namespace: str, key: str, value: str) -> None:
        self.command("annotate", "namespace", namespace, f"{key}={value}", "--overwrite")


def _integer(value: Any) -> int:
    return value if isinstance(value, int) and value >= 0 else 0


def _condition_true(item: dict[str, Any], condition_type: str) -> bool:
    conditions = item.get("status", {}).get("conditions", [])
    return any(
        isinstance(condition, dict)
        and condition.get("type") == condition_type
        and condition.get("status") == "True"
        for condition in conditions
    )


def workload_is_active(item: dict[str, Any]) -> bool:
    kind = item.get("kind")
    spec = item.get("spec", {})
    status_value = item.get("status", {})
    if kind in {"Deployment", "StatefulSet"}:
        return _integer(spec.get("replicas", 1)) > 0
    if kind in {"ReplicaSet", "ReplicationController"}:
        owners = item.get("metadata", {}).get("ownerReferences", [])
        return not owners and _integer(spec.get("replicas", 1)) > 0
    if kind == "DaemonSet":
        return True
    if kind == "Job":
        return (
            spec.get("suspend") is not True
            and not _condition_true(item, "Complete")
            and not _condition_true(item, "Failed")
        )
    if kind == "CronJob":
        return spec.get("suspend") is not True
    if kind == "Pod":
        owners = item.get("metadata", {}).get("ownerReferences", [])
        return not owners and status_value.get("phase") in {"Pending", "Running", "Unknown"}
    return False


def workload_is_healthy(item: dict[str, Any]) -> bool:
    if not workload_is_active(item):
        return True
    kind = item.get("kind")
    metadata = item.get("metadata", {})
    spec = item.get("spec", {})
    status_value = item.get("status", {})
    generation = _integer(metadata.get("generation"))
    observed = _integer(status_value.get("observedGeneration"))
    if kind == "Deployment":
        desired = _integer(spec.get("replicas", 1))
        return (
            observed >= generation
            and _integer(status_value.get("updatedReplicas")) == desired
            and _integer(status_value.get("availableReplicas")) == desired
            and _integer(status_value.get("readyReplicas")) == desired
        )
    if kind == "StatefulSet":
        desired = _integer(spec.get("replicas", 1))
        return (
            observed >= generation
            and _integer(status_value.get("updatedReplicas")) == desired
            and _integer(status_value.get("currentReplicas")) == desired
            and _integer(status_value.get("readyReplicas")) == desired
        )
    if kind in {"ReplicaSet", "ReplicationController"}:
        desired = _integer(spec.get("replicas", 1))
        return (
            observed >= generation
            and _integer(status_value.get("readyReplicas")) == desired
            and _integer(status_value.get("availableReplicas", desired)) == desired
        )
    if kind == "DaemonSet":
        desired = _integer(status_value.get("desiredNumberScheduled"))
        return (
            desired > 0
            and observed >= generation
            and _integer(status_value.get("updatedNumberScheduled")) == desired
            and _integer(status_value.get("numberReady")) == desired
            and _integer(status_value.get("numberUnavailable")) == 0
        )
    if kind == "Job":
        return not _condition_true(item, "Failed")
    if kind == "CronJob":
        return True
    if kind == "Pod":
        return status_value.get("phase") == "Running" and _condition_true(item, "Ready")
    return False


def count_active_workloads(items: Iterable[dict[str, Any]]) -> int:
    return sum(1 for item in items if workload_is_active(item))


def active_workloads_are_healthy(items: Iterable[dict[str, Any]]) -> bool:
    return all(workload_is_healthy(item) for item in items)


def long_running_workload_is_active(item: dict[str, Any]) -> bool:
    return workload_is_active(item) and item.get("kind") in {
        "Deployment",
        "StatefulSet",
        "DaemonSet",
        "ReplicaSet",
        "ReplicationController",
        "Pod",
    }


def observe_apiwpp(kubernetes: Kubernetes) -> tuple[str, int]:
    deployment = kubernetes.json(
        "-n", API_NAMESPACE, "get", "deployment", API_DEPLOYMENT
    )
    workloads = kubernetes.namespace_workloads(API_NAMESPACE)
    active_count = count_active_workloads(workloads)
    pod_list = kubernetes.json(
        "-n", API_NAMESPACE, "get", "pod", "-l", API_RUNTIME_SELECTOR
    ).get("items", [])
    if not isinstance(pod_list, list):
        raise ContractError("lista de Pods APIWPP inválida")
    desired = _integer(deployment.get("spec", {}).get("replicas", 1))
    deployment_status = deployment.get("status", {})
    running_ready = sum(
        1
        for pod in pod_list
        if isinstance(pod, dict)
        and pod.get("status", {}).get("phase") == "Running"
        and _condition_true(pod, "Ready")
    )
    active = (
        desired == 1
        and _integer(deployment_status.get("replicas")) == 1
        and _integer(deployment_status.get("updatedReplicas")) == 1
        and _integer(deployment_status.get("availableReplicas")) == 1
        and _integer(deployment_status.get("readyReplicas")) == 1
        and len(pod_list) == 1
        and running_ready == 1
        and active_count == 1
    )
    suspended = (
        desired == 0
        and _integer(deployment_status.get("replicas")) == 0
        and _integer(deployment_status.get("updatedReplicas")) == 0
        and _integer(deployment_status.get("availableReplicas")) == 0
        and _integer(deployment_status.get("readyReplicas")) == 0
        and len(pod_list) == 0
        and active_count == 0
    )
    if active:
        return "active", 1
    if suspended:
        return "suspended", 0
    return "ambiguous", active_count


def observe_saferwpp(kubernetes: Kubernetes) -> tuple[int, bool, bool]:
    total = 0
    healthy = True
    required_namespaces_active = True
    for namespace in SAFER_NAMESPACES:
        if not kubernetes.namespace_exists(namespace):
            required_namespaces_active = False
            continue
        workloads = kubernetes.namespace_workloads(namespace)
        total += count_active_workloads(workloads)
        healthy = healthy and active_workloads_are_healthy(workloads)
        required_namespaces_active = required_namespaces_active and any(
            long_running_workload_is_active(workload) for workload in workloads
        )
    return total, healthy, required_namespaces_active


def observe_runtime(kubernetes: Kubernetes) -> RuntimeObservation:
    api_state, api_count = observe_apiwpp(kubernetes)
    safer_count, safer_healthy, safer_namespaces_active = observe_saferwpp(kubernetes)
    return RuntimeObservation(
        api_state,
        api_count,
        safer_count,
        safer_healthy,
        safer_namespaces_active,
    )


def require_safer_namespaces(kubernetes: Kubernetes) -> None:
    missing = [name for name in SAFER_NAMESPACES if not kubernetes.namespace_exists(name)]
    if missing:
        raise ContractError(f"namespaces SaferWPP ausentes: {','.join(missing)}")


def set_namespace_gates(
    kubernetes: Kubernetes, occupant: str, generation: int, *, require_safer: bool
) -> None:
    if occupant not in OCCUPANTS:
        raise ContractError("ocupante inválido para o gate")
    if require_safer:
        require_safer_namespaces(kubernetes)
    members: list[tuple[str, str]] = [(API_NAMESPACE, "apiwpp")]
    members.extend((namespace, "saferwpp") for namespace in SAFER_NAMESPACES)
    existing = [entry for entry in members if kubernetes.namespace_exists(entry[0])]
    if not any(namespace == API_NAMESPACE for namespace, _ in existing):
        raise ContractError("namespace APIWPP ausente")
    for namespace, member in existing:
        kubernetes.label_namespace(namespace, MEMBER_LABEL, member)
        kubernetes.label_namespace(namespace, STATE_LABEL, "inactive")
        kubernetes.annotate_namespace(namespace, GENERATION_ANNOTATION, str(generation))
    if occupant != "none":
        for namespace, member in existing:
            if member == occupant:
                kubernetes.label_namespace(namespace, STATE_LABEL, "active")


def namespace_gates_match(kubernetes: Kubernetes, state: SlotState) -> bool:
    members: list[tuple[str, str]] = [(API_NAMESPACE, "apiwpp")]
    members.extend((namespace, "saferwpp") for namespace in SAFER_NAMESPACES)
    for namespace, member in members:
        if not kubernetes.namespace_exists(namespace):
            if member == "saferwpp" and state.active_occupant != "saferwpp":
                continue
            return False
        namespace_object = kubernetes.namespace(namespace)
        labels = namespace_object.get("metadata", {}).get("labels", {})
        annotations = namespace_object.get("metadata", {}).get("annotations", {})
        expected_state = "active" if state.active_occupant == member else "inactive"
        if labels.get(MEMBER_LABEL) != member or labels.get(STATE_LABEL) != expected_state:
            return False
        if annotations.get(GENERATION_ANNOTATION) != str(state.generation):
            return False
    return True


def state_matches_runtime(state: SlotState, runtime: RuntimeObservation) -> bool:
    if state.active_occupant == "apiwpp":
        return (
            runtime.apiwpp_state == ("active" if state.apiwpp_workloads == 1 else "suspended")
            and runtime.apiwpp_workloads == state.apiwpp_workloads
            and runtime.saferwpp_workloads == 0
        )
    if state.active_occupant == "saferwpp":
        return (
            runtime.apiwpp_state == "suspended"
            and runtime.apiwpp_workloads == 0
            and runtime.saferwpp_workloads == state.saferwpp_workloads
            and (
                state.saferwpp_workloads == 0
                or (
                    runtime.saferwpp_healthy
                    and runtime.saferwpp_required_namespaces_active
                )
            )
        )
    return (
        runtime.apiwpp_state == "suspended"
        and runtime.apiwpp_workloads == 0
        and runtime.saferwpp_workloads == 0
    )


def runtime_is_fully_suspended(runtime: RuntimeObservation) -> bool:
    return (
        runtime.apiwpp_state == "suspended"
        and runtime.apiwpp_workloads == 0
        and runtime.saferwpp_workloads == 0
    )


def activated_workload_counts(
    member: str, runtime: RuntimeObservation
) -> tuple[int, int]:
    if member == "apiwpp" and (
        runtime.apiwpp_state == "active"
        and runtime.apiwpp_workloads == 1
        and runtime.saferwpp_workloads == 0
    ):
        return 1, 0
    if member == "saferwpp" and (
        runtime.apiwpp_state == "suspended"
        and runtime.apiwpp_workloads == 0
        and runtime.saferwpp_workloads > 0
        and runtime.saferwpp_healthy
        and runtime.saferwpp_required_namespaces_active
    ):
        return 0, runtime.saferwpp_workloads
    raise ContractError("ativação ainda não está íntegra e Ready")


def state_from_unambiguous_runtime(
    generation: int, runtime: RuntimeObservation, updated_at: str
) -> SlotState:
    occupant = runtime.unambiguous_occupant
    if occupant == "apiwpp":
        return SlotState(generation, "apiwpp", 1, 0, updated_at)
    if occupant == "saferwpp":
        return SlotState(
            generation, "saferwpp", 0, runtime.saferwpp_workloads, updated_at
        )
    if occupant == "none":
        return SlotState(generation, "none", 0, 0, updated_at)
    raise ContractError("runtime ambíguo; nenhum lado pode ser atestado")


def _sanitized_resource(item: dict[str, Any]) -> dict[str, Any]:
    metadata = item.get("metadata", {})
    result: dict[str, Any] = {
        "apiVersion": item.get("apiVersion"),
        "kind": item.get("kind"),
        "metadata": {
            "name": metadata.get("name"),
            "namespace": metadata.get("namespace"),
            "labels": metadata.get("labels", {}),
            "annotations": {
                key: value
                for key, value in metadata.get("annotations", {}).items()
                if key
                not in {
                    "deployment.kubernetes.io/revision",
                    "kubectl.kubernetes.io/last-applied-configuration",
                }
            },
        },
        "spec": item.get("spec", {}),
    }
    if item.get("kind") == "Secret":
        result.pop("spec", None)
        result["type"] = item.get("type")
        result["immutable"] = item.get("immutable", False)
        data = item.get("data", {})
        result["data_sha256"] = {
            key: hashlib.sha256(str(value).encode("ascii")).hexdigest()
            for key, value in sorted(data.items())
        }
    elif item.get("kind") == "ConfigMap":
        result["data_sha256"] = {
            key: hashlib.sha256(str(value).encode("utf-8")).hexdigest()
            for key, value in sorted(item.get("data", {}).items())
        }
        try:
            result["binary_data_sha256"] = {
                key: hashlib.sha256(base64.b64decode(value, validate=True)).hexdigest()
                for key, value in sorted(item.get("binaryData", {}).items())
            }
        except (binascii.Error, ValueError) as error:
            raise ContractError("ConfigMap Blindou possui binaryData inválido") from error
    return result


def require_blindou_healthy_and_fingerprint(
    kubernetes: Kubernetes, current_release_file: pathlib.Path
) -> str:
    node = kubernetes.json("get", "node", "apiwpp")
    if not _condition_true(node, "Ready"):
        raise ContractError("nó K3s não está Ready")
    resources: list[dict[str, Any]] = []
    for namespace in BLINDOU_NAMESPACES:
        if not kubernetes.namespace_exists(namespace):
            raise ContractError(f"namespace Blindou ausente: {namespace}")
        workloads = kubernetes.namespace_workloads(namespace)
        if count_active_workloads(workloads) == 0:
            raise ContractError(f"Blindou sem workload ativo em {namespace}")
        if not active_workloads_are_healthy(workloads):
            raise ContractError(f"Blindou não está Ready em {namespace}")
        if not any(long_running_workload_is_active(item) for item in workloads):
            raise ContractError(
                f"Blindou sem workload contínuo ativo em {namespace}"
            )
        document = kubernetes.json(
            "-n", namespace, "get", BLINDOU_FINGERPRINT_RESOURCES
        )
        items = document.get("items")
        if not isinstance(items, list):
            raise ContractError(f"inventário Blindou inválido em {namespace}")
        resources.extend(item for item in items if isinstance(item, dict))
    require_secure_regular_file(current_release_file)
    release = current_release_file.read_text(encoding="utf-8").strip()
    if not RELEASE_PATTERN.fullmatch(release):
        raise ContractError("release corrente do Blindou é inválida")
    canonical = {
        "release": release,
        "resources": sorted(
            (_sanitized_resource(item) for item in resources),
            key=lambda item: (
                str(item.get("metadata", {}).get("namespace")),
                str(item.get("kind")),
                str(item.get("metadata", {}).get("name")),
            ),
        ),
    }
    payload = json.dumps(canonical, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def admission_is_installed(
    kubernetes: Kubernetes, manifest: pathlib.Path | None = None
) -> bool:
    for kind, name in (
        ("validatingadmissionpolicy", "secondary-slot-inactive-workloads"),
        ("validatingadmissionpolicybinding", "secondary-slot-inactive-workloads"),
        ("validatingadmissionpolicybinding", "secondary-slot-uninitialized-workloads"),
    ):
        if not kubernetes.runner.succeeds(("k3s", "kubectl", "get", kind, name)):
            return False
    if manifest is not None:
        require_secure_regular_file(manifest, 0o644)
        return kubernetes.runner.succeeds(
            ("k3s", "kubectl", "diff", "-f", str(manifest))
        )
    return True


def apply_admission(kubernetes: Kubernetes, manifest: pathlib.Path) -> None:
    require_secure_regular_file(manifest, 0o644)
    kubernetes.command("apply", "-f", str(manifest))
    if not admission_is_installed(kubernetes, manifest):
        raise ContractError("admissão do slot não ficou disponível e íntegra")


def validate_operation_id(operation_id: str) -> None:
    if not OPERATION_PATTERN.fullmatch(operation_id):
        raise ContractError("operation_id inválido")


def validate_fingerprint(fingerprint: str) -> None:
    if not SHA256_PATTERN.fullmatch(fingerprint):
        raise ContractError("fingerprint Blindou inválido")
