#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
readonly LC_ALL='C'
export LC_ALL
umask 077

readonly EXPECTED_HOSTNAME='apiwpp'
SOURCE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_DIRECTORY
REPOSITORY_ROOT="$(cd "${SOURCE_DIRECTORY}/../.." && pwd)"
readonly REPOSITORY_ROOT
readonly FOUNDATION_SOURCE="${REPOSITORY_ROOT}/platform/dre/controller-foundation.yaml"
readonly EDGE_RUNTIME_SOURCE="${REPOSITORY_ROOT}/platform/dre/edge-runtime.yaml"
readonly CONTROLLER_ALERTS_SOURCE="${REPOSITORY_ROOT}/platform/dre/monitoring/prometheus-alerts.yaml"
readonly VERIFIER_SOURCE="${SOURCE_DIRECTORY}/dre-release-verify.py"
readonly SECRET_SOURCE="${SOURCE_DIRECTORY}/dre-secret-material.py"
readonly VALIDATION_MATERIAL_SOURCE="${SOURCE_DIRECTORY}/dre-validation-material.py"
readonly RESTORE_SOURCE="${SOURCE_DIRECTORY}/dre-restore-render.py"
readonly CONTROLLER_SOURCE="${SOURCE_DIRECTORY}/dre-deployctl"
readonly IDENTITY_SOURCE="${SOURCE_DIRECTORY}/dre-kube-identityctl"
readonly SUDOERS_SOURCE="${SOURCE_DIRECTORY}/dre-deployctl.sudoers"
readonly LOGROTATE_SOURCE="${SOURCE_DIRECTORY}/dre-deployctl.logrotate"
readonly IDENTITY_SERVICE_SOURCE="${SOURCE_DIRECTORY}/dre-kube-identity.service"
readonly IDENTITY_TIMER_SOURCE="${SOURCE_DIRECTORY}/dre-kube-identity.timer"
readonly METRICS_SERVICE_SOURCE="${SOURCE_DIRECTORY}/dre-controller-metrics.service"
readonly METRICS_TIMER_SOURCE="${SOURCE_DIRECTORY}/dre-controller-metrics.timer"
readonly ARTIFACT_VERIFIER="${SOURCE_DIRECTORY}/verify-dre-controller-artifacts.py"
readonly VALIDATION_ACCESS_SOURCE="${REPOSITORY_ROOT}/platform/dre/validation-access.yaml"
readonly K3S='/usr/local/bin/k3s'
readonly CONFIG_ROOT='/etc/dre-deployctl'
readonly LIB_ROOT='/usr/local/lib/dre-deployctl'
readonly STATE_ROOT='/var/lib/dre-deployctl'
readonly INBOX='/home/apiadmin/dre-deploy-inbox'
readonly PROMETHEUS_CONFIG='/etc/prometheus/prometheus.yml'
readonly PROMETHEUS_RULES='/etc/prometheus/rules/dre-controller.yml'
readonly BACKUP_ROOT='/var/backups/servidor-local/dre-controller-bootstrap'
readonly PLATFORM_BOOTSTRAP_LOCK='/run/lock/servidor-local-platform-bootstrap.lock'

fail() {
  printf '[bootstrap-dre-deployctl] ERRO: %s\n' "$*" >&2
  exit 1
}

report_unhandled_error() {
  local code="$1"
  local line="$2"
  printf '[bootstrap-dre-deployctl] ERRO: comando interno falhou na linha %s (código %s)\n' \
    "$line" "$code" >&2
  return "$code"
}

trap 'report_unhandled_error "$?" "$LINENO"' ERR

require_empty_namespace() {
  local namespace="$1"
  local -a resources=(
    deployments.apps statefulsets.apps daemonsets.apps replicasets.apps
    replicationcontrollers jobs.batch cronjobs.batch pods services
    persistentvolumeclaims secrets
  )
  local resource count
  for resource in "${resources[@]}"; do
    count="$("$K3S" kubectl --namespace "$namespace" get "$resource" \
      --ignore-not-found -o name | wc -l)"
    [[ "$count" -eq 0 ]] \
      || fail "namespace ${namespace} contém ${count} objeto(s) ${resource} inesperado(s)"
  done
}

restore_configuration_fingerprint() {
  if ! "$K3S" kubectl --namespace dre-restore-drill get pvc dre-restore-data \
      >/dev/null 2>&1; then
    printf absent
    return
  fi
  local pv_name
  pv_name="$("$K3S" kubectl --namespace dre-restore-drill get pvc dre-restore-data \
    -o jsonpath='{.spec.volumeName}')"
  {
    "$K3S" kubectl --namespace dre-restore-drill get pvc dre-restore-data -o json \
      | jq -cS '{apiVersion,kind,metadata:{name:.metadata.name,namespace:.metadata.namespace,uid:.metadata.uid,labels:.metadata.labels,annotations:.metadata.annotations,finalizers:.metadata.finalizers},spec,status:{phase:.status.phase}}'
    "$K3S" kubectl get pv "$pv_name" -o json \
      | jq -cS '{apiVersion,kind,metadata:{name:.metadata.name,uid:.metadata.uid,labels:.metadata.labels,annotations:.metadata.annotations,finalizers:.metadata.finalizers},spec,status:{phase:.status.phase}}'
  } | sha256sum | cut -d' ' -f1
}

require_restore_bootstrap_state() {
  local pvc_names
  pvc_names="$("$K3S" kubectl --namespace dre-restore-drill get pvc \
    --ignore-not-found -o name | sort)"
  if [[ -z "$pvc_names" ]]; then
    require_empty_namespace dre-restore-drill
    return
  fi
  [[ "$pvc_names" == 'persistentvolumeclaim/dre-restore-data' ]] \
    || fail "inventário PVC do restore preservado diverge: ${pvc_names}"
  local pvc_json operation_id receipt release_id pvc_uid pv_name
  for resource in deployments.apps statefulsets.apps daemonsets.apps replicasets.apps \
      replicationcontrollers jobs.batch cronjobs.batch pods services secrets; do
    require_exact_names dre-restore-drill "$resource" ''
  done
  require_exact_names dre-restore-drill persistentvolumeclaims \
    'persistentvolumeclaim/dre-restore-data'
  pvc_json="$("$K3S" kubectl --namespace dre-restore-drill \
    get pvc dre-restore-data -o json)"
  jq -e '
    .metadata.labels["app.kubernetes.io/name"] == "dre-restore-postgres" and
    .metadata.labels["app.kubernetes.io/component"] == "restore-drill" and
    .metadata.labels["app.kubernetes.io/part-of"] == "dre-familiar" and
    .metadata.labels["app.kubernetes.io/managed-by"] == "dre-deployctl" and
    (.metadata.labels["dre.familiar/operation-id"] | test("^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$")) and
    .spec.storageClassName == "dre-local-delete-drill" and
    .spec.accessModes == ["ReadWriteOnce"] and
    .spec.resources.requests.storage == "20Gi" and
    .status.phase == "Bound" and
    (.spec.volumeName | test("^pvc-[0-9a-f-]{36}$"))
  ' <<<"$pvc_json" >/dev/null \
    || fail 'PVC de restore preservado diverge do contrato fechado'
  operation_id="$(jq -r '.metadata.labels["dre.familiar/operation-id"]' <<<"$pvc_json")"
  receipt="${STATE_ROOT}/receipts/restore-${operation_id}.json"
  [[ -f "$receipt" && ! -L "$receipt" \
      && "$(stat -c '%U:%G:%a:%h' "$receipt")" == 'root:root:600:1' ]] \
    || fail 'recibo do restore falho está ausente ou inseguro'
  [[ -f "${STATE_ROOT}/current-release" && ! -L "${STATE_ROOT}/current-release" ]] \
    || fail 'restore preservado exige release corrente'
  release_id="$(<"${STATE_ROOT}/current-release")"
  jq -e --arg release_id "$release_id" --arg operation_id "$operation_id" '
    .schema == 1 and .status == "failed" and .release_id == $release_id and
    .operation_id == $operation_id
  ' "$receipt" >/dev/null || fail 'recibo não comprova restore falho preservado'
  pvc_uid="$(jq -r '.metadata.uid' <<<"$pvc_json")"
  pv_name="$(jq -r '.spec.volumeName' <<<"$pvc_json")"
  "$K3S" kubectl get pv "$pv_name" -o json \
    | jq -e --arg pvc_uid "$pvc_uid" '
      .spec.storageClassName == "dre-local-delete-drill" and
      .spec.persistentVolumeReclaimPolicy == "Delete" and
      .spec.claimRef.namespace == "dre-restore-drill" and
      .spec.claimRef.name == "dre-restore-data" and
      .spec.claimRef.uid == $pvc_uid
    ' >/dev/null || fail 'PV de restore preservado diverge do PVC fechado'
}

require_production_predeploy_state() {
  local -a resources=(
    deployments.apps statefulsets.apps daemonsets.apps replicasets.apps
    replicationcontrollers jobs.batch cronjobs.batch pods services
    persistentvolumeclaims
  )
  local resource count secret_names
  for resource in "${resources[@]}"; do
    count="$("$K3S" kubectl --namespace dre-production get "$resource" \
      --ignore-not-found -o name | wc -l)"
    [[ "$count" -eq 0 ]] \
      || fail "namespace dre-production contém ${count} objeto(s) ${resource} antes do deploy"
  done
  secret_names="$("$K3S" kubectl --namespace dre-production get secrets -o json \
    | jq -r '.items[].metadata.name' | sort)"
  case "$secret_names" in
    '') ;;
    $'dre-api-runtime\ndre-backup-runtime\ndre-database-access\ndre-postgres-admin\ndre-registry-pull') ;;
    $'dre-api-runtime\ndre-backup-runtime\ndre-database-access\ndre-fcm-runtime\ndre-postgres-admin\ndre-registry-pull') ;;
    *) fail 'inventário de Secrets de produção diverge do estado pré-deploy aprovado' ;;
  esac
  [[ "$("$K3S" kubectl get namespace dre-production -o jsonpath='{.metadata.labels.platform\.servidor\.local/deployment-gate}')" =~ ^(blocked|secrets-only)$ ]] \
    || fail 'gate de produção já avançou além do estado autorizado para o bootstrap'
}

require_exact_names() {
  local namespace="$1"
  local resource="$2"
  local expected="$3"
  local actual
  actual="$("$K3S" kubectl --namespace "$namespace" get "$resource" \
    --ignore-not-found -o name | sort)"
  [[ "$actual" == "$expected" ]] \
    || fail "inventário ${resource} de ${namespace} diverge da recuperação fechada"
}

latest_failed_deploy_receipt() {
  local receipt
  receipt="$(find "${STATE_ROOT}/receipts" -maxdepth 1 -type f \
    -name 'deploy-*.json' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)"
  [[ -n "$receipt" && -f "$receipt" && ! -L "$receipt" \
      && "$(stat -c '%U:%G:%a:%h' "$receipt")" == 'root:root:600:1' ]] \
    || fail 'recibo do deploy falho está ausente ou inseguro'
  jq -e \
    '.schema == 1 and .status == "failed" and .previous_release == "none" and .rollback == "passed" and (.release_id | test("^dre-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$"))' \
    "$receipt" >/dev/null || fail 'recibo não comprova rollback do primeiro deploy'
  printf '%s' "$receipt"
}

require_production_failed_first_deploy_state() {
  local receipt release_id postgres_image status relation_absent
  [[ ! -e "${STATE_ROOT}/current-release" && ! -L "${STATE_ROOT}/current-release" ]] \
    || fail 'recuperação do primeiro deploy exige ausência de release corrente'
  receipt="$(latest_failed_deploy_receipt)"
  release_id="$(jq -r '.release_id' "$receipt")"
  [[ -f "${STATE_ROOT}/releases/${release_id}/extracted/release.json" \
      && ! -L "${STATE_ROOT}/releases/${release_id}/extracted/release.json" ]] \
    || fail 'release do deploy falho não está no cache fechado'
  postgres_image="$(jq -r '.postgres_image' \
    "${STATE_ROOT}/releases/${release_id}/extracted/release.json")"
  [[ "$postgres_image" =~ ^[a-z0-9][a-z0-9._:/-]*@sha256:[0-9a-f]{64}$ ]] \
    || fail 'imagem PostgreSQL do deploy falho é inválida'
  status="$(sudo -u apiadmin sudo -n /usr/local/sbin/dre-deployctl status)"
  jq -e \
    '.schema == 2 and .release == "none" and .gate == "secrets-only" and .pvc_phase == "Bound" and .ready == {api:0,worker:0,postgres:1} and .edge.gate == "blocked" and .edge.ready == 0 and .validation.gate == "absent"' \
    <<<"$status" >/dev/null || fail 'status não corresponde ao primeiro deploy revertido'
  require_exact_names dre-production deployments.apps ''
  require_exact_names dre-production statefulsets.apps 'statefulset.apps/dre-postgres'
  require_exact_names dre-production daemonsets.apps ''
  require_exact_names dre-production replicasets.apps ''
  require_exact_names dre-production replicationcontrollers ''
  require_exact_names dre-production jobs.batch ''
  require_exact_names dre-production cronjobs.batch ''
  require_exact_names dre-production pods 'pod/dre-postgres-0'
  require_exact_names dre-production services 'service/dre-postgres'
  require_exact_names dre-production persistentvolumeclaims \
    'persistentvolumeclaim/dre-postgres-data'
  [[ "$("$K3S" kubectl --namespace dre-production get statefulset dre-postgres \
      -o jsonpath='{.spec.replicas}:{.status.readyReplicas}:{.spec.template.spec.containers[0].image}')" \
      == "1:1:${postgres_image}" ]] \
    || fail 'StatefulSet preservado não corresponde ao PostgreSQL da release falha'
  [[ "$("$K3S" kubectl --namespace dre-production get pvc dre-postgres-data \
      -o jsonpath='{.status.phase}:{.spec.storageClassName}:{.spec.resources.requests.storage}')" \
      == 'Bound:dre-local-retain:20Gi' ]] \
    || fail 'PVC preservado diverge do volume retido aprovado'
  relation_absent="$("$K3S" kubectl --namespace dre-production exec dre-postgres-0 \
    --container postgres -- psql --no-psqlrc --tuples-only --no-align \
    -h /var/run/postgresql -U dre_postgres_admin -d dre \
    --command="SELECT to_regclass('public._sqlx_migrations') IS NULL")"
  [[ "${relation_absent//[[:space:]]/}" == t ]] \
    || fail 'recuperação fechada exige falha anterior às migrations'
}

production_recovery_fingerprint() {
  {
    "$K3S" kubectl get namespace dre-production -o json \
      | jq -cS '{kind,metadata:{name:.metadata.name,uid:.metadata.uid,labels:.metadata.labels,annotations:.metadata.annotations}}'
    "$K3S" kubectl --namespace dre-production \
      get deployments.apps,statefulsets.apps,daemonsets.apps,replicasets.apps,replicationcontrollers,jobs.batch,cronjobs.batch,pods,services,persistentvolumeclaims,configmaps,secrets,serviceaccounts,limitranges,resourcequotas,networkpolicies.networking.k8s.io,poddisruptionbudgets.policy \
      -o json \
      | jq -cS '[.items[] | {
          apiVersion,kind,
          metadata:{name:.metadata.name,uid:.metadata.uid,labels:.metadata.labels,annotations:.metadata.annotations,ownerReferences:.metadata.ownerReferences},
          spec,data,stringData,type,immutable
        }] | sort_by(.kind,.metadata.name)'
  } | sha256sum | cut -d' ' -f1
}

require_production_active_release_state() {
  local current_release_file="${STATE_ROOT}/current-release"
  local release_id status
  [[ -f "$current_release_file" && ! -L "$current_release_file" \
      && "$(stat -c '%U:%G:%a:%h' "$current_release_file")" == 'root:root:600:1' \
      && "$(wc -l <"$current_release_file")" -eq 1 ]] \
    || fail 'release corrente está ausente ou insegura para atualizar o controlador'
  release_id="$(<"$current_release_file")"
  [[ "$release_id" =~ ^dre-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$ ]] \
    || fail 'release corrente possui identificador inválido'
  [[ -f "${STATE_ROOT}/releases/${release_id}/extracted/release.json" \
      && ! -L "${STATE_ROOT}/releases/${release_id}/extracted/release.json" ]] \
    || fail 'release corrente não está no cache fechado'
  jq -e '
    .schema == 2 and
    .namespace == "dre-production" and
    .migration_count == 9 and
    (.rust_image | test("@sha256:[0-9a-f]{64}$")) and
    (.postgres_image | test("@sha256:[0-9a-f]{64}$"))
  ' "${STATE_ROOT}/releases/${release_id}/extracted/release.json" >/dev/null \
    || fail 'release corrente não possui o contrato persistente schema 2'
  status="$(sudo -u apiadmin sudo -n /usr/local/sbin/dre-deployctl status)"
  jq -e --arg release_id "$release_id" '
    .schema == 2 and
    .release == $release_id and
    .gate == "passed" and
    .pvc_phase == "Bound" and
    .ready == {api:1,worker:1,postgres:1} and
    .validation.gate == "absent" and
    ((.edge.gate == "blocked" and .edge.ready == 0) or
     (.edge.gate == "connector-only" and .edge.ready == 1))
  ' <<<"$status" >/dev/null \
    || fail 'status não corresponde a uma release ativa e saudável'
  if "$K3S" kubectl --namespace dre-production get pod dre-account-provisioner \
      >/dev/null 2>&1; then
    fail 'Pod administrativo efêmero existe durante a atualização do controlador'
  fi
  sudo -u apiadmin sudo -n /usr/local/sbin/dre-deployctl verify "$release_id" \
    >/dev/null || fail 'release ativa não passou pela verificação fechada do controlador'
}

edge_configuration_fingerprint() {
  if ! "$K3S" kubectl get namespace dre-edge >/dev/null 2>&1; then
    printf absent
    return
  fi
  {
    "$K3S" kubectl get namespace dre-edge -o json \
      | jq -cS '{kind,metadata:{name:.metadata.name,uid:.metadata.uid,labels:.metadata.labels,annotations:.metadata.annotations}}'
    "$K3S" kubectl --namespace dre-edge \
      get deployments.apps,statefulsets.apps,daemonsets.apps,replicasets.apps,replicationcontrollers,jobs.batch,cronjobs.batch,pods,services,persistentvolumeclaims,configmaps,secrets,serviceaccounts,limitranges,resourcequotas,networkpolicies.networking.k8s.io,poddisruptionbudgets.policy,roles.rbac.authorization.k8s.io,rolebindings.rbac.authorization.k8s.io \
      -o json \
      | jq -cS '[.items[] | {
          apiVersion,kind,
          metadata:{name:.metadata.name,uid:.metadata.uid,labels:.metadata.labels,annotations:.metadata.annotations,ownerReferences:.metadata.ownerReferences},
          spec,data,stringData,type,immutable,automountServiceAccountToken,rules,roleRef,subjects
        }] | sort_by(.kind,.metadata.name)'
  } | sha256sum | cut -d' ' -f1
}

require_edge_bootstrap_state() {
  local mode="$1" gate deployments secrets pods prohibited
  if ! "$K3S" kubectl get namespace dre-edge >/dev/null 2>&1; then
    [[ "$mode" != active-release ]] \
      || fail 'namespace dre-edge está ausente para a release ativa'
    return
  fi
  [[ "$("$K3S" kubectl get namespace dre-edge \
    -o jsonpath='{.metadata.labels.platform\.servidor\.local/project}')" == dre ]] \
    || fail 'namespace dre-edge saiu do ownership DRE'
  gate="$("$K3S" kubectl get namespace dre-edge \
    -o jsonpath='{.metadata.labels.platform\.servidor\.local/deployment-gate}')"
  if [[ "$mode" != active-release || "$gate" == blocked ]]; then
    [[ "$gate" == blocked ]] \
      || fail 'bootstrap pré-release exige dre-edge bloqueada'
    require_empty_namespace dre-edge
    return
  fi
  [[ "$gate" == connector-only ]] \
    || fail 'gate do edge da release ativa é inválido'
  deployments="$("$K3S" kubectl --namespace dre-edge get deployments.apps \
    -o json | jq -r '[.items[].metadata.name] | sort | join(",")')"
  secrets="$("$K3S" kubectl --namespace dre-edge get secrets \
    -o json | jq -r '[.items[].metadata.name] | sort | join(",")')"
  pods="$("$K3S" kubectl --namespace dre-edge get pods \
    -l app.kubernetes.io/name=dre-cloudflared -o json \
    | jq -r '[.items[]] | length')"
  prohibited="$("$K3S" kubectl --namespace dre-edge \
    get statefulsets.apps,daemonsets.apps,replicationcontrollers,jobs.batch,cronjobs.batch,services,persistentvolumeclaims \
    -o json | jq -r '[.items[]] | length')"
  [[ "$deployments" == dre-cloudflared && "$secrets" == dre-cloudflare-tunnel \
      && "$pods" == 1 && "$prohibited" == 0 \
      && "$("$K3S" kubectl --namespace dre-edge get deployment dre-cloudflared \
        -o jsonpath='{.spec.replicas}:{.status.availableReplicas}')" == '1:1' ]] \
    || fail 'runtime do edge da release ativa diverge do inventário fechado'
}

require_validation_namespace_absent() {
  ! "$K3S" kubectl get namespace dre-validation >/dev/null 2>&1 \
    || fail 'dre-validation existe; concluir diagnóstico/limpeza antes de atualizar o controlador'
}

require_validation_bootstrap_state() {
  local gate project lifecycle release_id operation_id deletion_timestamp
  if ! "$K3S" kubectl get namespace dre-validation >/dev/null 2>&1; then
    return
  fi
  gate="$("$K3S" kubectl get namespace dre-validation \
    -o jsonpath='{.metadata.labels.platform\.servidor\.local/deployment-gate}')"
  project="$("$K3S" kubectl get namespace dre-validation \
    -o jsonpath='{.metadata.labels.platform\.servidor\.local/project}')"
  lifecycle="$("$K3S" kubectl get namespace dre-validation \
    -o jsonpath='{.metadata.labels.dre\.familiar/lifecycle}')"
  release_id="$("$K3S" kubectl get namespace dre-validation \
    -o jsonpath='{.metadata.labels.dre\.familiar/release-id}')"
  operation_id="$("$K3S" kubectl get namespace dre-validation \
    -o jsonpath='{.metadata.labels.dre\.familiar/operation-id}')"
  deletion_timestamp="$("$K3S" kubectl get namespace dre-validation \
    -o jsonpath='{.metadata.deletionTimestamp}')"
  [[ "$gate" == blocked && "$project" == dre && "$lifecycle" == disposable ]] \
    || fail 'dre-validation existente não é uma validação DRE bloqueada'
  [[ "$release_id" =~ ^dre-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$ ]] \
    || fail 'release ID da validação bloqueada é inválido'
  [[ "$operation_id" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$ ]] \
    || fail 'operation ID da validação bloqueada é inválido'
  [[ -z "$deletion_timestamp" ]] || fail 'dre-validation está em remoção'
}

validation_configuration_fingerprint() {
  if ! "$K3S" kubectl get namespace dre-validation >/dev/null 2>&1; then
    printf absent
    return
  fi
  {
    "$K3S" kubectl get namespace dre-validation -o json \
      | jq -cS '{kind,metadata:{name:.metadata.name,uid:.metadata.uid,labels:.metadata.labels}}'
    "$K3S" kubectl --namespace dre-validation \
      get deployments.apps,statefulsets.apps,services,persistentvolumeclaims,jobs.batch,configmaps,secrets \
      -o json \
      | jq -cS '[.items[] | {
          apiVersion,kind,
          metadata:{name:.metadata.name,uid:.metadata.uid,labels:.metadata.labels,annotations:.metadata.annotations},
          spec,data,stringData,type,immutable
        }] | sort_by(.kind,.metadata.name)'
  } | sha256sum | cut -d' ' -f1
}

wait_for_protected_locks_release() {
  local -a lock_files=(
    /run/lock/apiwpp-deploy.lock
    /run/lock/blindou-deployctl.lock
  )
  local lock_file lock_fd
  for lock_file in "${lock_files[@]}"; do
    [[ -f "$lock_file" && ! -L "$lock_file" ]] \
      || fail "lock protegido ausente ou inseguro: ${lock_file}"
    exec {lock_fd}<>"$lock_file"
    if ! flock --timeout 90 "$lock_fd"; then
      exec {lock_fd}>&-
      fail "lock protegido não foi liberado em 90 segundos: ${lock_file}"
    fi
    flock --unlock "$lock_fd"
    exec {lock_fd}>&-
  done
}

run_protected_gate() {
  local label="$1"
  local busy_message="$2"
  shift 2
  local output attempt code line
  output="$(mktemp)"
  for ((attempt = 1; attempt <= 12; attempt++)); do
    if "$@" >"$output" 2>&1; then
      rm -f -- "$output"
      return 0
    else
      code=$?
    fi
    if [[ "$code" -ne 2 ]] || ! grep -Fq -- "$busy_message" "$output"; then
      while IFS= read -r line; do
        printf '[bootstrap-dre-deployctl] %s: %s\n' "$label" "$line" >&2
      done <"$output"
      rm -f -- "$output"
      fail "${label} não está íntegro"
    fi
    if [[ "$attempt" -lt 12 ]]; then
      sleep 5
    fi
  done
  rm -f -- "$output"
  fail "${label} permaneceu ocupado por 60 segundos"
}

run_secondary_slot_gate() {
  local output occupant apiwpp_workloads saferwpp_workloads
  output="$(sudo -u apiadmin sudo -n /usr/local/sbin/secondary-slotctl verify)" \
    || fail 'slot secundário não está íntegro'
  if [[ "$output" =~ ^secondary_slot_verify=passed[[:space:]]occupant=(none|apiwpp|saferwpp)[[:space:]]generation=([0-9]+)[[:space:]]apiwpp_workloads=([0-9]+)[[:space:]]saferwpp_workloads=([0-9]+)$ ]]; then
    occupant="${BASH_REMATCH[1]}"
    apiwpp_workloads="${BASH_REMATCH[3]}"
    saferwpp_workloads="${BASH_REMATCH[4]}"
  else
    fail 'atestado do slot secundário possui formato inesperado'
  fi
  case "$occupant" in
    none)
      [[ "$apiwpp_workloads" == 0 && "$saferwpp_workloads" == 0 ]] \
        || fail 'slot none possui workload ativo'
      ;;
    apiwpp)
      [[ "$saferwpp_workloads" == 0 ]] || fail 'slot APIWPP possui workload SaferWPP'
      if [[ "$apiwpp_workloads" != 0 ]]; then
        run_protected_gate APIWPP 'another apiwpp deployment is already running' \
          sudo -u apiadmin sudo -n /usr/local/sbin/apiwpp-deployctl verify
      fi
      ;;
    saferwpp)
      [[ "$apiwpp_workloads" == 0 && "$saferwpp_workloads" != 0 ]] \
        || fail 'slot SaferWPP possui contagem incompatível'
      [[ -x /usr/local/sbin/saferwpp-deployctl \
        && ! -L /usr/local/sbin/saferwpp-deployctl ]] \
        || fail 'SaferWPP ocupante não possui controlador fechado'
      sudo -u apiadmin sudo -n /usr/local/sbin/saferwpp-deployctl verify >/dev/null \
        || fail 'SaferWPP ocupante não está íntegro'
      ;;
  esac
}

reset_dre_unit_failures() {
  local unit
  for unit in dre-controller-metrics.service dre-controller-metrics.timer \
    dre-kube-identity.service dre-kube-identity.timer; do
    systemctl reset-failed "$unit" >/dev/null 2>&1 || true
  done
}

[[ "$#" -eq 2 ]] || fail 'uso: bootstrap-dre-deployctl.sh PUBLIC_KEY PUBLIC_KEY_SHA256'
readonly PUBLIC_KEY="$1"
readonly PUBLIC_KEY_SHA256="$2"
[[ "${EUID}" -eq 0 ]] || fail 'execute como root em janela autorizada'
[[ "$(hostname)" == "$EXPECTED_HOSTNAME" ]] || fail 'hostname inesperado'
[[ "$PUBLIC_KEY_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail 'SHA-256 da chave pública inválido'

for command in python3 openssl sudo visudo promtool logrotate systemd-analyze install cp mv rm mkdir base64 \
  chmod chown stat sha256sum systemctl jq grep flock hostname date find wc mktemp sleep sort head cut "$K3S"; do
  command -v "$command" >/dev/null || fail "dependência ausente: ${command}"
done
for source in "$FOUNDATION_SOURCE" "$EDGE_RUNTIME_SOURCE" "$CONTROLLER_ALERTS_SOURCE" "$VERIFIER_SOURCE" \
  "$SECRET_SOURCE" "$VALIDATION_MATERIAL_SOURCE" "$RESTORE_SOURCE" "$CONTROLLER_SOURCE" "$IDENTITY_SOURCE" \
  "$SUDOERS_SOURCE" "$LOGROTATE_SOURCE" "$IDENTITY_SERVICE_SOURCE" "$IDENTITY_TIMER_SOURCE" \
  "$METRICS_SERVICE_SOURCE" "$METRICS_TIMER_SOURCE" "$ARTIFACT_VERIFIER" \
  "$VALIDATION_ACCESS_SOURCE" \
  "$PUBLIC_KEY"; do
  [[ -f "$source" && ! -L "$source" ]] || fail "fonte ausente ou simbólica: ${source}"
done
[[ "$(sha256sum "$PUBLIC_KEY" | cut -d' ' -f1)" == "$PUBLIC_KEY_SHA256" ]] \
  || fail 'SHA-256 da chave pública diverge'
openssl pkey -pubin -in "$PUBLIC_KEY" -text -noout \
  | grep -F 'ED25519 Public-Key' >/dev/null || fail 'trust root deve ser Ed25519'
[[ "$($K3S --version | head -n 1)" == 'k3s version v1.36.2+k3s1 '* ]] \
  || fail 'versão K3s diferente de v1.36.2+k3s1'
[[ "$(uname -m)" == x86_64 ]] || fail 'nó não é x86_64'

python3 "$ARTIFACT_VERIFIER"
visudo -cf "$SUDOERS_SOURCE" >/dev/null
logrotate --debug "$LOGROTATE_SOURCE" >/dev/null 2>&1
promtool check rules "$CONTROLLER_ALERTS_SOURCE" >/dev/null
for controller in /usr/local/sbin/apiwpp-deployctl \
  /usr/local/sbin/blindou-deployctl /usr/local/sbin/secondary-slotctl; do
  [[ -x "$controller" && ! -L "$controller" ]] \
    || fail "controlador de proteção ausente: ${controller}"
done
reset_dre_unit_failures
wait_for_protected_locks_release
run_protected_gate Blindou 'outra operação Blindou está em andamento' \
  sudo -u apiadmin sudo -n /usr/local/sbin/blindou-deployctl status
wait_for_protected_locks_release
run_secondary_slot_gate

exec 6>"$PLATFORM_BOOTSTRAP_LOCK"
chmod 0600 "$PLATFORM_BOOTSTRAP_LOCK"
flock --nonblock 6 || fail 'outro bootstrap de plataforma está em andamento'
platform_lock_held=true

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup="${BACKUP_ROOT}/${timestamp}"
mkdir -p "$backup"
chmod 0700 "$backup"
rollback_needed=true
foundation_created=false
production_gate_before='blocked'
production_secret_count=0
production_bootstrap_mode=predeploy
production_fingerprint_before=absent
edge_fingerprint_before=absent
validation_fingerprint_before=absent
restore_fingerprint_before=absent
declare -a targets=(
  /usr/local/sbin/dre-deployctl
  /usr/local/sbin/dre-kube-identityctl
  /usr/local/lib/dre-deployctl/dre-release-verify.py
  /usr/local/lib/dre-deployctl/dre-secret-material.py
  /usr/local/lib/dre-deployctl/dre-validation-material.py
  /usr/local/lib/dre-deployctl/validation-access.yaml
  /usr/local/lib/dre-deployctl/dre-restore-render.py
  /usr/local/lib/dre-deployctl/edge-runtime.yaml
  /etc/dre-deployctl/release-signing.pub
  /etc/dre-deployctl/client.key
  /etc/dre-deployctl/client.crt
  /etc/dre-deployctl/kubeconfig
  /etc/sudoers.d/dre-deployctl
  /etc/logrotate.d/dre-deployctl
  /etc/systemd/system/dre-kube-identity.service
  /etc/systemd/system/dre-kube-identity.timer
  /etc/systemd/system/dre-controller-metrics.service
  /etc/systemd/system/dre-controller-metrics.timer
  /var/lib/prometheus/node-exporter/dre-controller.prom
  "$PROMETHEUS_RULES"
  "$PROMETHEUS_CONFIG"
)

for target in "${targets[@]}"; do
  if [[ -e "$target" || -L "$target" ]]; then
    [[ -f "$target" && ! -L "$target" ]] || fail "alvo preexistente inseguro: ${target}"
    relative="${target#/}"
    mkdir -p "${backup}/$(dirname "$relative")"
    chmod 0700 "${backup}/$(dirname "$relative")"
    cp -a -- "$target" "${backup}/${relative}"
  fi
done
printf '%s\n' "${targets[@]}" >"${backup}/targets.txt"
chmod 0600 "${backup}/targets.txt"

rollback() {
  local code=$?
  if $rollback_needed; then
    set +e
    if ! $platform_lock_held; then
      exec 6>"$PLATFORM_BOOTSTRAP_LOCK"
      chmod 0600 "$PLATFORM_BOOTSTRAP_LOCK"
      if ! flock --timeout 30 6; then
        printf '[bootstrap-dre-deployctl] ERRO: rollback não readquiriu o lock global\n' >&2
        exit 70
      fi
      platform_lock_held=true
    fi
    systemctl disable --now dre-controller-metrics.timer dre-kube-identity.timer >/dev/null 2>&1
    if $foundation_created; then
      "$K3S" kubectl delete -f "$FOUNDATION_SOURCE" --ignore-not-found >/dev/null 2>&1 || true
    fi
    for target in "${targets[@]}"; do
      relative="${target#/}"
      if [[ -f "${backup}/${relative}" ]]; then
        mkdir -p "$(dirname "$target")"
        cp -a -- "${backup}/${relative}" "$target"
      else
        rm -f -- "$target"
      fi
    done
    systemctl daemon-reload
    reset_dre_unit_failures
    if promtool check config "$PROMETHEUS_CONFIG" >/dev/null 2>&1; then
      systemctl reload prometheus.service >/dev/null 2>&1 || true
    fi
  fi
  exit "$code"
}
trap rollback EXIT
reset_dre_unit_failures

if "$K3S" kubectl get validatingadmissionpolicy dre-controller-only >/dev/null 2>&1; then
  if "$K3S" kubectl --namespace dre-production get statefulset dre-postgres \
      >/dev/null 2>&1; then
    if [[ -f "${STATE_ROOT}/current-release" \
        && ! -L "${STATE_ROOT}/current-release" ]]; then
      production_bootstrap_mode=active-release
      require_production_active_release_state
      edge_fingerprint_before="$(edge_configuration_fingerprint)"
    else
      production_bootstrap_mode=failed-first-deploy
      require_production_failed_first_deploy_state
    fi
    production_fingerprint_before="$(production_recovery_fingerprint)"
  else
    require_production_predeploy_state
  fi
  require_edge_bootstrap_state "$production_bootstrap_mode"
  require_restore_bootstrap_state
  restore_fingerprint_before="$(restore_configuration_fingerprint)"
  require_validation_bootstrap_state
  validation_fingerprint_before="$(validation_configuration_fingerprint)"
  if [[ "$production_bootstrap_mode" == predeploy ]]; then
    production_gate_before="$(
      "$K3S" kubectl get namespace dre-production \
        -o jsonpath='{.metadata.labels.platform\.servidor\.local/deployment-gate}'
    )"
    production_secret_count="$(
      "$K3S" kubectl --namespace dre-production get secrets -o json \
        | jq '.items | length'
    )"
    "$K3S" kubectl apply -f "$FOUNDATION_SOURCE" >/dev/null
    if [[ "$production_gate_before" == secrets-only \
        || "$production_secret_count" -ge 5 ]]; then
      "$K3S" kubectl label namespace dre-production \
        platform.servidor.local/deployment-gate=secrets-only \
        --overwrite >/dev/null
    fi
  fi
else
  require_validation_namespace_absent
  foundation_created=true
  "$K3S" kubectl apply -f "$FOUNDATION_SOURCE" >/dev/null
fi
case "$production_bootstrap_mode" in
  failed-first-deploy) require_production_failed_first_deploy_state ;;
  active-release) require_production_active_release_state ;;
  predeploy) require_production_predeploy_state ;;
  *) fail 'modo interno de bootstrap DRE inválido' ;;
esac
require_edge_bootstrap_state "$production_bootstrap_mode"
require_restore_bootstrap_state
[[ "$(restore_configuration_fingerprint)" == "$restore_fingerprint_before" ]] \
  || fail 'PVC do restore falho mudou antes da atualização do controlador'
require_validation_bootstrap_state

install -d -m 0700 -o root -g root "$CONFIG_ROOT" "$LIB_ROOT" "$STATE_ROOT" \
  "${STATE_ROOT}/releases" "${STATE_ROOT}/plans" "${STATE_ROOT}/receipts"
install -d -m 0700 -o apiadmin -g apiadmin "$INBOX"
install -m 0755 -o root -g root "$CONTROLLER_SOURCE" /usr/local/sbin/dre-deployctl
install -m 0700 -o root -g root "$IDENTITY_SOURCE" /usr/local/sbin/dre-kube-identityctl
install -m 0500 -o root -g root "$VERIFIER_SOURCE" "${LIB_ROOT}/dre-release-verify.py"
install -m 0500 -o root -g root "$SECRET_SOURCE" "${LIB_ROOT}/dre-secret-material.py"
install -m 0500 -o root -g root "$VALIDATION_MATERIAL_SOURCE" "${LIB_ROOT}/dre-validation-material.py"
install -m 0600 -o root -g root "$VALIDATION_ACCESS_SOURCE" "${LIB_ROOT}/validation-access.yaml"
install -m 0500 -o root -g root "$RESTORE_SOURCE" "${LIB_ROOT}/dre-restore-render.py"
install -m 0600 -o root -g root "$EDGE_RUNTIME_SOURCE" "${LIB_ROOT}/edge-runtime.yaml"
install -m 0644 -o root -g root "$PUBLIC_KEY" "${CONFIG_ROOT}/release-signing.pub"
install -m 0440 -o root -g root "$SUDOERS_SOURCE" /etc/sudoers.d/dre-deployctl
visudo -cf /etc/sudoers.d/dre-deployctl >/dev/null
install -m 0644 -o root -g root "$LOGROTATE_SOURCE" /etc/logrotate.d/dre-deployctl
install -m 0644 -o root -g root "$IDENTITY_SERVICE_SOURCE" /etc/systemd/system/dre-kube-identity.service
install -m 0644 -o root -g root "$IDENTITY_TIMER_SOURCE" /etc/systemd/system/dre-kube-identity.timer
install -m 0644 -o root -g root "$METRICS_SERVICE_SOURCE" /etc/systemd/system/dre-controller-metrics.service
install -m 0644 -o root -g root "$METRICS_TIMER_SOURCE" /etc/systemd/system/dre-controller-metrics.timer
install -m 0644 -o root -g root "$CONTROLLER_ALERTS_SOURCE" "$PROMETHEUS_RULES"
for unit in /etc/systemd/system/dre-kube-identity.service \
  /etc/systemd/system/dre-kube-identity.timer \
  /etc/systemd/system/dre-controller-metrics.service \
  /etc/systemd/system/dre-controller-metrics.timer; do
  systemd-analyze verify "$unit" >/dev/null
done

python3 - "$PROMETHEUS_CONFIG" "$PROMETHEUS_RULES" <<'PY'
import os
import pathlib
import sys
import yaml

config_path = pathlib.Path(sys.argv[1])
rules_path = sys.argv[2]
config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
if not isinstance(config, dict):
    raise SystemExit("configuração Prometheus inválida")
rule_files = config.setdefault("rule_files", [])
if not isinstance(rule_files, list):
    raise SystemExit("rule_files Prometheus inválido")
if rules_path not in rule_files:
    rule_files.append(rules_path)
metadata = config_path.stat()
temporary = config_path.with_name(config_path.name + ".dre.tmp")
temporary.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
temporary.chmod(metadata.st_mode & 0o777)
os.chown(temporary, metadata.st_uid, metadata.st_gid)
temporary.replace(config_path)
PY
promtool check config "$PROMETHEUS_CONFIG" >/dev/null

/usr/local/sbin/dre-kube-identityctl reconcile >/dev/null
/usr/local/sbin/dre-kube-identityctl verify >/dev/null
sudo -u apiadmin sudo -n /usr/local/sbin/dre-deployctl contract \
  | jq -e '.schema == 2 and .controller == "dre-deployctl" and .edge_namespace == "dre-edge" and .validation_namespace == "dre-validation" and .validation.required_before_plan == true and .postgres_upgrade.requires_current_backup_after_plan == true and .postgres_upgrade.only_postgres_digest_change == true and .postgres_upgrade.rollback == true and (.read_only | index("diagnose-production")) != null and (.mutations | index("configure-edge")) != null and (.mutations | index("provision-accounts")) != null and (.mutations | index("upgrade-postgres")) != null and .generic_shell == false and .secondary_slot_member == false and .bridge_token_source == "orchestrator-stdin" and .edge_token_source == "orchestrator-stdin"' \
  >/dev/null

negative_manifest="$(mktemp)"
cat >"$negative_manifest" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: dre-untrusted-proof
  namespace: dre-production
spec:
  automountServiceAccountToken: false
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: proof
      image: registry.invalid/proof@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      command: ["/bin/false"]
      resources:
        requests: {cpu: 10m, memory: 32Mi}
        limits: {cpu: 10m, memory: 32Mi}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: {drop: ["ALL"]}
        readOnlyRootFilesystem: true
YAML
if "$K3S" kubectl apply --dry-run=server --as=dre-untrusted -f "$negative_manifest" \
    >/dev/null 2>&1; then
  rm -f -- "$negative_manifest"
  fail 'admissão aceitou alteração fora do controlador DRE'
fi
rm -f -- "$negative_manifest"

systemctl daemon-reload
systemctl enable --now dre-kube-identity.timer >/dev/null
systemctl start --wait dre-controller-metrics.service
promtool check metrics </var/lib/prometheus/node-exporter/dre-controller.prom >/dev/null
systemctl enable --now dre-controller-metrics.timer >/dev/null
systemctl reload prometheus.service
[[ "$(systemctl show dre-controller-metrics.service --property=Result --value)" == success ]] \
  || fail 'coleta inicial de métricas falhou'
flock --unlock 6
exec 6>&-
platform_lock_held=false
wait_for_protected_locks_release
run_protected_gate Blindou 'outra operação Blindou está em andamento' \
  sudo -u apiadmin sudo -n /usr/local/sbin/blindou-deployctl status
wait_for_protected_locks_release
run_secondary_slot_gate
case "$production_bootstrap_mode" in
  failed-first-deploy)
    require_production_failed_first_deploy_state
    [[ "$(production_recovery_fingerprint)" == "$production_fingerprint_before" ]] \
      || fail 'runtime preservado mudou durante o bootstrap de diagnóstico'
    ;;
  active-release)
    require_production_active_release_state
    [[ "$(production_recovery_fingerprint)" == "$production_fingerprint_before" ]] \
      || fail 'runtime da release ativa mudou durante a atualização do controlador'
    [[ "$(edge_configuration_fingerprint)" == "$edge_fingerprint_before" ]] \
      || fail 'runtime do edge mudou durante a atualização do controlador'
    ;;
  predeploy) require_production_predeploy_state ;;
  *) fail 'modo interno de bootstrap DRE inválido' ;;
esac
require_restore_bootstrap_state
[[ "$(restore_configuration_fingerprint)" == "$restore_fingerprint_before" ]] \
  || fail 'PVC do restore falho mudou durante a atualização do controlador'
require_validation_bootstrap_state
[[ "$(validation_configuration_fingerprint)" == "$validation_fingerprint_before" ]] \
  || fail 'configuração da validação bloqueada mudou durante o bootstrap'

rollback_needed=false
trap - ERR EXIT
printf 'dre_controller_bootstrap=installed public_key_sha256=%s backup=%s\n' \
  "$PUBLIC_KEY_SHA256" "$backup"
