#!/usr/bin/env python3
"""Gate offline do namespace de dados Blindou, sem acesso ao cluster."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, NoReturn

import yaml


def fail(message: str) -> NoReturn:
    raise SystemExit(f"[verify-blindou-data-artifacts] ERRO: {message}")


def read_documents(path: Path) -> list[dict[str, Any]]:
    documents = list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
    if not documents or any(not isinstance(document, dict) for document in documents):
        fail(f"YAML vazio ou inválido: {path}")
    return documents


def main() -> int:
    if len(sys.argv) != 2:
        fail("uso: verify-blindou-data-artifacts.py REPOSITORY_ROOT")
    root = Path(sys.argv[1]).resolve()
    data_root = root / "platform" / "blindou-data"
    if not data_root.is_dir() or data_root.is_symlink():
        fail("diretório de plataforma ausente, inválido ou simbólico")
    expected_files = {
        "00-namespace.yaml",
        "10-quarantine.yaml",
        "20-workload-policy.yaml",
        "kustomization.yaml",
    }
    entries = list(data_root.iterdir())
    actual_files = {path.name for path in entries}
    if (
        actual_files != expected_files
        or any(not path.is_file() or path.is_symlink() for path in entries)
    ):
        fail("pacote de plataforma não contém exatamente os arquivos autorizados")

    documents: list[dict[str, Any]] = []
    for name in ("00-namespace.yaml", "10-quarantine.yaml", "20-workload-policy.yaml"):
        documents.extend(read_documents(data_root / name))
    if any(document.get("kind") == "Secret" for document in documents):
        fail("fundação de dados não pode conter Secret")
    namespace_documents = [document for document in documents if document.get("kind") == "Namespace"]
    if len(namespace_documents) != 1:
        fail("era esperado exatamente um Namespace")
    namespace = namespace_documents[0]
    if namespace.get("metadata", {}).get("name") != "blindou-data":
        fail("namespace dedicado divergente")
    labels = namespace["metadata"]["labels"]
    expected_labels = {
        "platform.servidor.local/managed": "true",
        "platform.servidor.local/project": "blindou",
        "platform.servidor.local/environment": "production",
        "platform.servidor.local/role": "data",
        "platform.servidor.local/deployment-gate": "blocked",
        "pod-security.kubernetes.io/enforce": "restricted",
        "pod-security.kubernetes.io/enforce-version": "v1.36",
        "pod-security.kubernetes.io/audit": "restricted",
        "pod-security.kubernetes.io/audit-version": "v1.36",
        "pod-security.kubernetes.io/warn": "restricted",
        "pod-security.kubernetes.io/warn-version": "v1.36",
    }
    if labels != expected_labels:
        fail("labels do namespace de dados divergentes")
    if namespace["metadata"].get("annotations") != {
        "platform.servidor.local/gate-reason": "dedicated-data-controller-not-installed"
    }:
        fail("motivo fail-closed do gate divergente")

    cluster_scoped = {
        "Namespace",
        "ValidatingAdmissionPolicy",
        "ValidatingAdmissionPolicyBinding",
    }
    for document in documents:
        if document.get("kind") not in cluster_scoped and document.get(
            "metadata", {}
        ).get("namespace") != "blindou-data":
            fail("objeto da fundação escapou do namespace blindou-data")
    service_account = next(
        document for document in documents if document.get("kind") == "ServiceAccount"
    )
    if service_account.get("metadata", {}).get("name") != "default" or service_account.get(
        "automountServiceAccountToken"
    ) is not False:
        fail("ServiceAccount default não está fechada")
    quota = next(document for document in documents if document.get("kind") == "ResourceQuota")
    if {key: str(value) for key, value in quota["spec"]["hard"].items()} != {
        "pods": "0",
        "services": "0",
        "secrets": "0",
        "persistentvolumeclaims": "0",
        "configmaps": "1",
    }:
        fail("quarentena não bloqueia todos os objetos operacionais")
    policy = next(document for document in documents if document.get("kind") == "NetworkPolicy")
    if policy.get("metadata", {}).get("name") != "platform-default-deny" or policy.get(
        "spec"
    ) != {"podSelector": {}, "policyTypes": ["Ingress", "Egress"]}:
        fail("default deny do namespace de dados diverge")

    admission = next(
        document
        for document in documents
        if document.get("kind") == "ValidatingAdmissionPolicy"
    )
    binding = next(
        document
        for document in documents
        if document.get("kind") == "ValidatingAdmissionPolicyBinding"
    )
    if admission.get("metadata", {}).get("name") != "blindou-data-workload-baseline":
        fail("política de admissão de dados divergente")
    expressions = "\n".join(
        validation.get("expression", "")
        for validation in admission.get("spec", {}).get("validations", [])
    )
    for required in (
        "pull-only",
        "candidate-foundation",
        "postgres-pull-proof",
        "blindou-postgresql-0",
        "ghcr.io/gleisonsette/blindou-postgres@sha256:",
    ):
        if required not in expressions:
            fail(f"política de admissão não contém: {required}")
    selector = binding.get("spec", {}).get("matchResources", {}).get(
        "namespaceSelector", {}
    ).get("matchLabels", {})
    if selector != {
        "platform.servidor.local/environment": "production",
        "platform.servidor.local/role": "data",
    }:
        fail("binding da admissão de dados escapou do namespace dedicado")

    application_policy = read_documents(
        root / "platform" / "blindou" / "20-production-workload-policy.yaml"
    )
    application_binding = next(
        document
        for document in application_policy
        if document.get("kind") == "ValidatingAdmissionPolicyBinding"
        and document.get("metadata", {}).get("name")
        == "managed-production-workload-baseline"
    )
    match_expressions = application_binding.get("spec", {}).get(
        "matchResources", {}
    ).get("namespaceSelector", {}).get("matchExpressions")
    if match_expressions != [
        {
            "key": "platform.servidor.local/role",
            "operator": "In",
            "values": ["application", "edge"],
        }
    ]:
        fail("admissão geral não exclui o papel data de sua política")

    kustomization = yaml.safe_load((data_root / "kustomization.yaml").read_text(encoding="utf-8"))
    if kustomization.get("resources") != [
        "00-namespace.yaml",
        "10-quarantine.yaml",
        "20-workload-policy.yaml",
    ]:
        fail("kustomization inclui recurso não autorizado")
    print("[verify-blindou-data-artifacts] fundação bloqueada válida")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
