#!/usr/bin/env python3
"""Provisiona e confere o catálogo Pagar.me do Blindou sem expor credenciais."""

from __future__ import annotations

import argparse
import base64
import json
import os
import random
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


API_BASE = "https://api.pagar.me/core/v5"
CATALOG_VERSION = "0005"
USER_AGENT = "BlindouCatalogOperator/1.0"
SECRET_KEY_PATTERN = re.compile(r"^sk_[A-Za-z0-9]{16,509}$")
PLAN_ID_PATTERN = re.compile(r"^plan_[A-Za-z0-9]{16,64}$")
REDACT_SECRET_PATTERN = re.compile(
    r"(?i)\b(?:sk|pk)_(?:test_)?[A-Za-z0-9]{8,}\b|"
    r"\bBasic\s+[A-Za-z0-9+/=]{12,}\b|"
    r"https://api\.blindou\.com/webhooks/pagarme/[A-Za-z0-9_-]+"
)


class ProvisioningError(RuntimeError):
    pass


@dataclass(frozen=True)
class PlanSpec:
    code: str
    name: str
    description: str
    price_cents: int


CATALOG = (
    PlanSpec(
        "iniciante",
        "Iniciante",
        "Para quem está começando a montar sua operação",
        29_700,
    ),
    PlanSpec(
        "operador_junior",
        "Operador Júnior",
        "Para quem já colocou a operação para rodar",
        49_700,
    ),
    PlanSpec(
        "operador_pleno",
        "Operador Pleno",
        "Para quem já opera com consistência e quer crescer",
        89_700,
    ),
    PlanSpec(
        "operador_senior",
        "Operador Sênior",
        "Para operações maduras que precisam de mais escala",
        99_700,
    ),
    PlanSpec(
        "elite_i",
        "Elite I",
        "Para quem entrou no nível das grandes operações",
        249_700,
    ),
    PlanSpec(
        "elite_ii",
        "Elite II",
        "Para operações de alta escala",
        379_700,
    ),
    PlanSpec(
        "elite_iii",
        "Elite III",
        "Para operações de altíssima escala e grande volume",
        749_700,
    ),
)


def fail(message: str) -> None:
    raise ProvisioningError(message)


def safe_text(value: object, limit: int = 800) -> str:
    text = REDACT_SECRET_PATTERN.sub("<credencial-removida>", str(value))
    text = " ".join(text.split())
    return text if len(text) <= limit else f"{text[:limit]}…"


def safe_provider_error(body: bytes) -> str:
    try:
        parsed = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return "sem detalhe estruturado"
    parts: list[str] = []
    if isinstance(parsed, dict):
        message = parsed.get("message")
        if isinstance(message, str) and message.strip():
            parts.append(message)
        errors = parsed.get("errors")
        if isinstance(errors, dict):
            for field, values in list(errors.items())[:12]:
                candidates = values if isinstance(values, list) else [values]
                for value in candidates[:4]:
                    if isinstance(value, str) and value.strip():
                        parts.append(f"{field}: {value}")
    return safe_text("; ".join(parts) if parts else "sem detalhe estruturado")


def load_secret_key(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        fail("arquivo da secret key Pagar.me ausente ou simbólico")
    stat = path.stat()
    if stat.st_uid != 0 or (stat.st_mode & 0o777) != 0o600:
        fail("arquivo da secret key Pagar.me não é root-only")
    value = path.read_text(encoding="utf-8").strip()
    if not SECRET_KEY_PATTERN.fullmatch(value) or value.startswith("sk_test_"):
        fail("secret key guardada não pertence ao ambiente live esperado")
    return value


class PagarmeClient:
    def __init__(self, secret_key: str) -> None:
        credential = base64.b64encode(f"{secret_key}:".encode("ascii")).decode("ascii")
        self._authorization = f"Basic {credential}"
        self._ssl_context = ssl.create_default_context()

    def close(self) -> None:
        self._authorization = ""

    def request(
        self,
        method: str,
        path: str,
        *,
        body: dict[str, Any] | None = None,
        idempotency_key: str | None = None,
        retry_safe: bool,
    ) -> Any:
        if not re.fullmatch(r"/plans(?:/[A-Za-z0-9_-]+)?(?:\?.*)?", path):
            fail("o provisionador tentou acessar recurso externo não permitido")
        url = urllib.parse.urljoin(f"{API_BASE}/", path.lstrip("/"))
        parsed = urllib.parse.urlsplit(url)
        if (
            parsed.scheme != "https"
            or parsed.hostname != "api.pagar.me"
            or not parsed.path.startswith("/core/v5/plans")
        ):
            fail("a URL resolvida saiu do endpoint fixo de planos Pagar.me")
        encoded_body = None
        headers = {
            "Accept": "application/json",
            "Authorization": self._authorization,
            "User-Agent": USER_AGENT,
        }
        if body is not None:
            encoded_body = json.dumps(
                body, ensure_ascii=False, separators=(",", ":")
            ).encode("utf-8")
            headers["Content-Type"] = "application/json; charset=utf-8"
        if idempotency_key is not None:
            headers["Idempotency-Key"] = idempotency_key

        attempts = 3 if retry_safe else 1
        for attempt in range(1, attempts + 1):
            request = urllib.request.Request(
                url, data=encoded_body, headers=headers, method=method
            )
            try:
                with urllib.request.urlopen(
                    request, timeout=30, context=self._ssl_context
                ) as response:
                    response_body = response.read(2 * 1024 * 1024 + 1)
                    if len(response_body) > 2 * 1024 * 1024:
                        fail("Pagar.me respondeu acima do limite operacional de 2 MiB")
                    if not response_body:
                        fail("Pagar.me respondeu sem JSON na operação de planos")
                    try:
                        return json.loads(response_body.decode("utf-8"))
                    except (UnicodeDecodeError, json.JSONDecodeError) as error:
                        raise ProvisioningError(
                            "Pagar.me respondeu com JSON inválido na operação de planos"
                        ) from error
            except urllib.error.HTTPError as error:
                response_body = error.read(256 * 1024)
                if retry_safe and error.code in {429, 500, 502, 503, 504} and attempt < attempts:
                    time.sleep((2 ** (attempt - 1)) + random.uniform(0.05, 0.35))
                    continue
                fail(
                    "Pagar.me recusou a operação de planos com HTTP "
                    f"{error.code}. Detalhe: {safe_provider_error(response_body)}"
                )
            except (TimeoutError, urllib.error.URLError) as error:
                if retry_safe and attempt < attempts:
                    time.sleep((2 ** (attempt - 1)) + random.uniform(0.05, 0.35))
                    continue
                operation = "consulta" if retry_safe else "criação"
                fail(
                    f"Falha de rede durante a {operation} de planos; "
                    "nenhum retry cego de criação foi executado"
                )
        fail("a consulta Pagar.me excedeu o limite de tentativas")

    def all_plans(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for page in range(1, 51):
            response = self.request(
                "GET", f"/plans?page={page}&size=30", retry_safe=True
            )
            if isinstance(response, dict) and isinstance(response.get("data"), list):
                page_plans = response["data"]
            elif isinstance(response, list):
                page_plans = response
            else:
                fail("a listagem de planos retornou um contrato desconhecido")
            if any(not isinstance(plan, dict) for plan in page_plans):
                fail("a listagem de planos contém item em formato desconhecido")
            result.extend(page_plans)
            if len(page_plans) < 30:
                return result
        fail("a listagem de planos excedeu o limite operacional de 1.500 itens")

    def plan(self, plan_id: str) -> dict[str, Any]:
        if not PLAN_ID_PATTERN.fullmatch(plan_id):
            fail("Pagar.me retornou ID de plano inválido")
        response = self.request("GET", f"/plans/{plan_id}", retry_safe=True)
        if not isinstance(response, dict):
            fail("o detalhe do plano retornou contrato desconhecido")
        return response

    def create_plan(self, spec: PlanSpec) -> dict[str, Any]:
        response = self.request(
            "POST",
            "/plans",
            body=payload_for(spec),
            idempotency_key=f"blindou-catalog-{CATALOG_VERSION}-{spec.code}",
            retry_safe=False,
        )
        if not isinstance(response, dict):
            fail("a criação do plano retornou contrato desconhecido")
        return response

    def update_plan(self, plan_id: str, spec: PlanSpec) -> dict[str, Any]:
        if not PLAN_ID_PATTERN.fullmatch(plan_id):
            fail("Pagar.me retornou ID de plano inválido para correção")
        body = payload_for(spec)
        body["status"] = "active"
        response = self.request(
            "PUT",
            f"/plans/{plan_id}",
            body=body,
            idempotency_key=f"blindou-catalog-{CATALOG_VERSION}-{spec.code}-repair",
            retry_safe=False,
        )
        if not isinstance(response, dict):
            fail("a correção do plano retornou contrato desconhecido")
        return response


def payload_for(spec: PlanSpec) -> dict[str, Any]:
    return {
        "name": spec.name,
        "description": spec.description,
        "shippable": False,
        "payment_methods": ["credit_card"],
        "installments": [1],
        "minimum_price": spec.price_cents,
        "statement_descriptor": "BLINDOU",
        "currency": "BRL",
        "interval": "month",
        "interval_count": 1,
        "billing_type": "prepaid",
        "items": [
            {
                "name": spec.name,
                "quantity": 1,
                "pricing_scheme": {
                    "scheme_type": "unit",
                    "price": spec.price_cents,
                },
            }
        ],
        "metadata": {
            "blindou_catalog": "commercial",
            "blindou_catalog_code": spec.code,
            "blindou_catalog_version": CATALOG_VERSION,
        },
    }


def as_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def assert_plan(plan: dict[str, Any], spec: PlanSpec) -> None:
    plan_id = plan.get("id")
    if not isinstance(plan_id, str) or not PLAN_ID_PATTERN.fullmatch(plan_id):
        fail(f"plano {spec.code} possui ID externo inválido")
    expected = {
        "name": spec.name,
        "description": spec.description,
        "status": "active",
        "currency": "BRL",
        "interval": "month",
        "interval_count": 1,
        "minimum_price": spec.price_cents,
        "billing_type": "prepaid",
        "statement_descriptor": "BLINDOU",
    }
    for field, value in expected.items():
        actual = plan.get(field)
        if field in {"interval_count", "minimum_price"}:
            actual = as_int(actual)
        if actual != value:
            fail(f"plano {spec.code} diverge no campo {field}")
    if plan.get("shippable") not in {None, False}:
        fail(f"plano {spec.code} diverge no campo shippable")
    if plan.get("trial_period_days") not in {None, 0, "0"}:
        fail(f"plano {spec.code} possui trial não autorizado")
    if plan.get("payment_methods") != ["credit_card"]:
        fail(f"plano {spec.code} possui meios de pagamento divergentes")
    installments = plan.get("installments")
    if not isinstance(installments, list) or [as_int(item) for item in installments] != [1]:
        fail(f"plano {spec.code} possui parcelamento divergente")
    items = plan.get("items")
    if not isinstance(items, list) or len(items) != 1 or not isinstance(items[0], dict):
        fail(f"plano {spec.code} deve possuir um item")
    item = items[0]
    pricing = item.get("pricing_scheme")
    if (
        item.get("name") != spec.name
        or as_int(item.get("quantity")) != 1
        or not isinstance(pricing, dict)
        or pricing.get("scheme_type") != "unit"
        or as_int(pricing.get("price")) != spec.price_cents
    ):
        fail(f"plano {spec.code} possui item ou preço divergente")
    metadata = plan.get("metadata")
    if not isinstance(metadata, dict) or {
        "blindou_catalog": metadata.get("blindou_catalog"),
        "blindou_catalog_code": metadata.get("blindou_catalog_code"),
        "blindou_catalog_version": metadata.get("blindou_catalog_version"),
    } != {
        "blindou_catalog": "commercial",
        "blindou_catalog_code": spec.code,
        "blindou_catalog_version": CATALOG_VERSION,
    }:
        fail(f"plano {spec.code} possui metadata divergente")


def merge_plan_representations(
    summary: dict[str, Any], detail: dict[str, Any]
) -> dict[str, Any]:
    """Combina os contratos list/detail sem deixar null apagar dado já confirmado."""
    merged = dict(summary)
    merged.update({key: value for key, value in detail.items() if value is not None})
    return merged


def find_plan(
    client: PagarmeClient,
    plans: list[dict[str, Any]],
    spec: PlanSpec,
    *,
    repair_existing: bool = False,
) -> dict[str, Any] | None:
    matching: list[dict[str, Any]] = []
    for plan in plans:
        metadata = plan.get("metadata")
        if (
            isinstance(metadata, dict)
            and metadata.get("blindou_catalog_code") == spec.code
            and plan.get("status") != "deleted"
        ):
            matching.append(plan)
    if len(matching) > 1:
        fail(f"há mais de um plano vivo com o código {spec.code}")
    if matching:
        detailed = client.plan(str(matching[0].get("id", "")))
        normalized = merge_plan_representations(matching[0], detailed)
        try:
            assert_plan(normalized, spec)
            return normalized
        except ProvisioningError:
            if not repair_existing:
                raise
            plan_id = str(normalized.get("id", ""))
            try:
                updated = client.update_plan(plan_id, spec)
            except ProvisioningError as update_error:
                fetched = merge_plan_representations(
                    normalized, client.plan(plan_id)
                )
                try:
                    assert_plan(fetched, spec)
                except ProvisioningError:
                    raise ProvisioningError(
                        f"plano {spec.code} diverge e a correção não foi confirmada: "
                        f"{safe_text(update_error)}"
                    ) from update_error
                print(f"pagarme_plan_reconciled={spec.code}")
                return fetched
            fetched = merge_plan_representations(updated, client.plan(plan_id))
            assert_plan(fetched, spec)
            print(f"pagarme_plan_repaired={spec.code}")
            return fetched
    collisions = [
        plan
        for plan in plans
        if plan.get("name") == spec.name and plan.get("status") != "deleted"
    ]
    if collisions:
        fail(f"já existe plano vivo chamado {spec.name} sem a identidade canônica do Blindou")
    return None


def resolve_catalog(client: PagarmeClient, *, create_missing: bool) -> dict[str, dict[str, Any]]:
    listed = client.all_plans()
    resolved: dict[str, dict[str, Any]] = {}
    missing: list[PlanSpec] = []
    for spec in CATALOG:
        existing = find_plan(
            client, listed, spec, repair_existing=create_missing
        )
        if existing is None:
            missing.append(spec)
        else:
            resolved[spec.code] = existing
    if missing and not create_missing:
        fail(f"catálogo Pagar.me incompleto: {len(missing)} plano(s) ausente(s)")

    for spec in missing:
        fresh = client.all_plans()
        existing = find_plan(client, fresh, spec, repair_existing=True)
        if existing is not None:
            resolved[spec.code] = existing
            continue
        try:
            created = client.create_plan(spec)
            plan_id = created.get("id")
            detailed = client.plan(str(plan_id))
            normalized = merge_plan_representations(created, detailed)
            assert_plan(normalized, spec)
            resolved[spec.code] = normalized
            print(f"pagarme_plan_created={spec.code}")
        except ProvisioningError as original_error:
            reconciled = find_plan(
                client, client.all_plans(), spec, repair_existing=True
            )
            if reconciled is None:
                raise ProvisioningError(
                    f"criação de {spec.name} não foi confirmada e não será repetida "
                    f"automaticamente: {safe_text(original_error)}"
                ) from original_error
            resolved[spec.code] = reconciled
            print(f"pagarme_plan_reconciled={spec.code}")

    final_listing = client.all_plans()
    final: dict[str, dict[str, Any]] = {}
    for spec in CATALOG:
        verified = find_plan(client, final_listing, spec)
        if verified is None:
            fail(f"plano {spec.code} ausente na verificação final")
        final[spec.code] = verified
    return final


def receipt_for(plans: dict[str, dict[str, Any]]) -> dict[str, Any]:
    return {
        "schema": 1,
        "provider": "pagarme-v5",
        "environment": "production",
        "catalog_version": CATALOG_VERSION,
        "verified_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "plans": [
            {
                "code": spec.code,
                "pagarme_plan_id": plans[spec.code]["id"],
                "name": spec.name,
                "price_cents": spec.price_cents,
            }
            for spec in CATALOG
        ],
    }


def validate_receipt(receipt: Any) -> None:
    if not isinstance(receipt, dict):
        fail("recibo de planos não é um objeto JSON")
    if (
        receipt.get("schema") != 1
        or receipt.get("provider") != "pagarme-v5"
        or receipt.get("environment") != "production"
        or receipt.get("catalog_version") != CATALOG_VERSION
    ):
        fail("recibo de planos possui cabeçalho divergente")
    plans = receipt.get("plans")
    if not isinstance(plans, list) or len(plans) != len(CATALOG):
        fail("recibo de planos não contém os sete itens")
    for recorded, spec in zip(plans, CATALOG, strict=True):
        if not isinstance(recorded, dict):
            fail("recibo de planos contém item inválido")
        if (
            recorded.get("code") != spec.code
            or recorded.get("name") != spec.name
            or as_int(recorded.get("price_cents")) != spec.price_cents
            or not isinstance(recorded.get("pagarme_plan_id"), str)
            or not PLAN_ID_PATTERN.fullmatch(recorded["pagarme_plan_id"])
        ):
            fail(f"recibo diverge no plano {spec.code}")


def write_receipt(path: Path, receipt: dict[str, Any]) -> None:
    validate_receipt(receipt)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    parent_stat = path.parent.stat()
    if parent_stat.st_uid != 0 or (parent_stat.st_mode & 0o022):
        fail("diretório do recibo Pagar.me não é protegido por root")
    temporary = Path(f"{path}.tmp.{os.getpid()}")
    if temporary.exists() or temporary.is_symlink():
        fail("arquivo temporário inesperado no recibo de planos")
    payload = json.dumps(receipt, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chown(temporary, 0, 0)
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def read_and_validate_receipt(path: Path) -> None:
    if path.is_symlink() or not path.is_file():
        fail("recibo de planos Pagar.me ausente ou simbólico")
    stat = path.stat()
    if stat.st_uid != 0 or (stat.st_mode & 0o777) != 0o600:
        fail("recibo de planos Pagar.me não é root-only")
    try:
        receipt = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ProvisioningError("recibo de planos Pagar.me possui JSON inválido") from error
    validate_receipt(receipt)


def self_test() -> None:
    spec = CATALOG[0]
    fixture = payload_for(spec)
    if "trial_period_days" in fixture or fixture.get("shippable") is not False:
        fail("self-test detectou trial ou entrega física no payload")
    plan = {
        "id": "plan_ABCDEFGHIJKLMNOP",
        "name": spec.name,
        "description": spec.description,
        "status": "active",
        "currency": "BRL",
        "interval": "month",
        "interval_count": 1,
        "minimum_price": spec.price_cents,
        "billing_type": "prepaid",
        "statement_descriptor": "BLINDOU",
        "payment_methods": ["credit_card"],
        "installments": [1],
        "items": [
            {
                "name": spec.name,
                "quantity": 1,
                "pricing_scheme": {"scheme_type": "unit", "price": spec.price_cents},
            }
        ],
        "metadata": {
            "blindou_catalog": "commercial",
            "blindou_catalog_code": spec.code,
            "blindou_catalog_version": CATALOG_VERSION,
        },
    }
    assert_plan(plan, spec)
    assert_plan(merge_plan_representations(plan, {"description": None}), spec)
    plan["shippable"] = True
    try:
        assert_plan(plan, spec)
    except ProvisioningError:
        pass
    else:
        fail("self-test aceitou plano com entrega física")
    if len(CATALOG) != 7 or sum(item.price_cents for item in CATALOG) != 1_647_900:
        fail("self-test detectou divergência no catálogo")
    redaction_fixture = "key sk_" + ("A" * 16) + " and Basic " + ("Q" * 24)
    redacted = safe_text(redaction_fixture)
    if ("A" * 8) in redacted or ("Q" * 12) in redacted:
        fail("self-test detectou falha de redação")
    print("blindou_pagarme_plans_self_test=passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("provision", "verify", "verify-receipt", "self-test"), required=True)
    parser.add_argument("--secret-key-file", type=Path)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()

    if args.mode == "self-test":
        self_test()
        return 0
    if args.receipt is None:
        fail("caminho fixo do recibo é obrigatório")
    if args.mode == "verify-receipt":
        read_and_validate_receipt(args.receipt)
        print("pagarme_plans_receipt=valid")
        return 0
    if args.secret_key_file is None:
        fail("arquivo root-only da secret key é obrigatório")

    secret_key = load_secret_key(args.secret_key_file)
    client = PagarmeClient(secret_key)
    secret_key = ""
    try:
        plans = resolve_catalog(client, create_missing=args.mode == "provision")
        if args.mode == "provision":
            write_receipt(args.receipt, receipt_for(plans))
        else:
            read_and_validate_receipt(args.receipt)
        print(f"pagarme_plans_verified={len(plans)}")
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProvisioningError as error:
        print(f"[blindou-pagarme-plans] ERRO: {safe_text(error)}", file=sys.stderr)
        raise SystemExit(1) from None
