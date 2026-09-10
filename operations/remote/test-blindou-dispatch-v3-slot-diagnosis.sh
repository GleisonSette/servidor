#!/usr/bin/env bash
# Executa somente a função extraída, com banco e host substituídos por fixtures.
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
function_source="$(sed -n '/^diagnose_dispatch_v3_logical_slot()/,/^}/p' "$root/blindou-deployctl")"
[[ -n "$function_source" ]]
eval "$function_source"

fail() { printf '%s\n' "$*" >&2; exit 1; }
require_root_and_host() { [[ "${host_allowed:-yes}" == yes ]] || fail 'host recusado'; }
postgres_query() {
  [[ "$*" == '-d blindou -Atq' ]] || fail 'interface PostgreSQL não está fechada'
  local sql
  sql="$(</dev/stdin)"
  grep -Fq 'ISOLATION LEVEL REPEATABLE READ READ ONLY' <<<"$sql" \
    && grep -Fq "statement_timeout = '10s'" <<<"$sql" \
    && grep -Fq "lock_timeout = '1s'" <<<"$sql" \
    && grep -Fq "slot_name = 'blindou_dispatch_v3_outbox_slot'" <<<"$sql" \
    && grep -Fq 'invalidation_reason' <<<"$sql" \
    && grep -Fq 'EXISTS (SELECT 1 FROM public.dispatch_outbox_v3)' <<<"$sql" \
    && grep -Fq 'EXISTS (SELECT 1 FROM blindou_cdc_state.debezium_offset_storage)' <<<"$sql" \
    || fail 'consulta perdeu o escopo ou os limites'
  if grep -Eiq '\b(DELETE|TRUNCATE|INSERT|UPDATE|ALTER|DROP|CREATE|COPY)\b|SELECT \*|pg_(drop|create|replication_slot_advance|logi)' <<<"$sql"; then
    fail 'consulta contém operação ou leitura proibida'
  fi
  [[ "${query_result:-ok}" != error ]] || return 1
  [[ "${query_result:-ok}" != empty ]] || return 0
  printf '%s\n' '{"slot":{"active":false,"invalidation_reason":"wal_removed"},"rows_present":{"outbox":true}}'
}

result="$(diagnose_dispatch_v3_logical_slot)"
[[ "$result" == 'dispatch_v3_slot_diagnosis={"slot":{"active":false,"invalidation_reason":"wal_removed"},"rows_present":{"outbox":true}}' ]]
if (query_result=error; diagnose_dispatch_v3_logical_slot) >/dev/null 2>&1; then
  fail 'falha SQL foi aceita'
fi
if (query_result=empty; diagnose_dispatch_v3_logical_slot) >/dev/null 2>&1; then
  fail 'resposta vazia foi aceita'
fi
if (host_allowed=no; diagnose_dispatch_v3_logical_slot) >/dev/null 2>&1; then
  fail 'host incorreto foi aceito'
fi
printf 'dispatch_v3_slot_diagnosis_tests=passed positive=1 refusals=3\n'
