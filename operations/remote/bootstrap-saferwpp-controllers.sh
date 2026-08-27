#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
readonly LC_ALL='C'
export LC_ALL
umask 077

readonly EXPECTED_HOSTNAME='apiwpp'
readonly SOURCE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SOURCE_DIRECTORY}/../.." && pwd)"
readonly VERIFIER_SOURCE="${SOURCE_DIRECTORY}/verify-saferwpp-controller-release.py"
readonly PLATFORM_VERIFIER_SOURCE="${SOURCE_DIRECTORY}/verify-saferwpp-controller-platform.py"
readonly IDENTITY_CONTROLLER_SOURCE="${SOURCE_DIRECTORY}/saferwpp-kube-identityctl"
readonly IDENTITY_SERVICE_SOURCE="${SOURCE_DIRECTORY}/saferwpp-kube-identities.service"
readonly IDENTITY_TIMER_SOURCE="${SOURCE_DIRECTORY}/saferwpp-kube-identities.timer"
readonly ALERTS_SOURCE="${REPOSITORY_ROOT}/platform/saferwpp/monitoring/controller-alerts.yaml"
readonly PROMETHEUS_CONFIG='/etc/prometheus/prometheus.yml'
readonly RULES_TARGET='/etc/prometheus/rules/saferwpp-controllers.yml'
readonly BACKUP_ROOT='/var/backups/servidor-local/saferwpp-controller-bootstrap'
readonly K3S='/usr/local/bin/k3s'
readonly -a REQUIRED_NAMESPACES=('saferwpp-lab' 'saferdock-identity' 'saferdock-platform')

fail() {
  printf '[bootstrap-saferwpp-controllers] ERRO: %s\n' "$*" >&2
  exit 1
}

[[ "$#" -eq 5 ]] \
  || fail 'uso: bootstrap-saferwpp-controllers.sh ARCHIVE SHA256 PUBLIC_KEY RELEASE_ID GIT_COMMIT'
readonly ARCHIVE="$1"
readonly ARCHIVE_SHA256="$2"
readonly PUBLIC_KEY="$3"
readonly RELEASE_ID="$4"
readonly GIT_COMMIT="$5"

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'
[[ "$(hostname)" == "$EXPECTED_HOSTNAME" ]] || fail 'hostname inesperado'
[[ "$ARCHIVE_SHA256" =~ ^[a-f0-9]{64}$ ]] || fail 'SHA-256 inválido'
[[ "$GIT_COMMIT" =~ ^[a-f0-9]{40}$ ]] || fail 'commit inválido'
[[ "$RELEASE_ID" =~ ^swpc-[0-9]{8}T[0-9]{6}Z-${GIT_COMMIT:0:12}$ ]] \
  || fail 'release ID inválido ou divergente do commit'
for command in python3 openssl visudo promtool systemd-analyze systemd-tmpfiles \
  install cp sha256sum jq systemctl sudo bash grep stat cut mv rm chmod mkdir hostname \
  date "$K3S"; do
  command -v "$command" >/dev/null || fail "dependência ausente: ${command}"
done
for source in "$ARCHIVE" "$PUBLIC_KEY" "$VERIFIER_SOURCE" \
  "$PLATFORM_VERIFIER_SOURCE" \
  "$IDENTITY_CONTROLLER_SOURCE" "$IDENTITY_SERVICE_SOURCE" \
  "$IDENTITY_TIMER_SOURCE" "$ALERTS_SOURCE"; do
  [[ -f "$source" && ! -L "$source" ]] \
    || fail "fonte ausente ou simbólica: ${source}"
done
k3s_version="$($K3S --version)"
[[ "${k3s_version%%$'\n'*}" == 'k3s version v1.36.2+k3s1 '* ]] \
  || fail 'versão K3s diferente de v1.36.2+k3s1'
for controller in /usr/local/sbin/apiwpp-deployctl \
  /usr/local/sbin/blindou-deployctl /usr/local/sbin/secondary-slotctl; do
  [[ -x "$controller" && ! -L "$controller" ]] \
    || fail "controlador de proteção ausente ou simbólico: ${controller}"
done
/usr/local/sbin/apiwpp-deployctl verify >/dev/null \
  || fail 'APIWPP não está íntegro antes do bootstrap'
/usr/local/sbin/blindou-deployctl verify >/dev/null \
  || fail 'Blindou não está íntegro antes do bootstrap'
/usr/local/sbin/secondary-slotctl verify >/dev/null \
  || fail 'slot compartilhado não está íntegro antes do bootstrap'
python3 "$PLATFORM_VERIFIER_SOURCE"

for namespace in "${REQUIRED_NAMESPACES[@]}"; do
  namespace_json="$($K3S kubectl get namespace "$namespace" -o json)" \
    || fail "namespace obrigatório ausente: ${namespace}"
  expected_project="$namespace"
  if [[ "$namespace" == 'saferwpp-lab' ]]; then
    expected_project='saferwpp'
  fi
  [[ "$(jq -r '.metadata.labels["platform.servidor.local/project"] // ""' \
      <<<"$namespace_json")" == "$expected_project" ]] \
    || fail "label de projeto divergente em ${namespace}"
  [[ "$(jq -r '.metadata.labels["platform.servidor.local/secondary-slot-member"] // ""' \
      <<<"$namespace_json")" == 'saferwpp' ]] \
    || fail "membership do slot divergente em ${namespace}"
done

working_directory="$(mktemp -d -p /var/tmp saferwpp-controller-bootstrap.XXXXXX)"
readonly working_directory
[[ "$working_directory" == /var/tmp/saferwpp-controller-bootstrap.* \
    && -d "$working_directory" && ! -L "$working_directory" ]] \
  || fail 'diretório temporário inseguro'
remove_work_directory() {
  [[ "$working_directory" == /var/tmp/saferwpp-controller-bootstrap.* \
      && -d "$working_directory" && ! -L "$working_directory" ]] \
    || fail 'diretório temporário deixou de ser seguro'
  rm -rf -- "$working_directory"
}
cleanup_before_mutation() {
  local result="$?"
  trap - EXIT
  remove_work_directory
  exit "$result"
}
trap cleanup_before_mutation EXIT
readonly extracted="${working_directory}/release"
readonly verification_result="${working_directory}/verification.json"
readonly verified_public_key="${working_directory}/cosign.pub"
mkdir -m 0700 "$extracted"
install -o root -g root -m 0600 "$PUBLIC_KEY" "$verified_public_key"
python3 "$VERIFIER_SOURCE" "$ARCHIVE" "$verified_public_key" "$ARCHIVE_SHA256" \
  "$RELEASE_ID" "$GIT_COMMIT" --extract "$extracted" >"$verification_result"
jq -e --arg release "$RELEASE_ID" --arg commit "$GIT_COMMIT" \
  '.status == "passed" and .releaseId == $release and .gitCommit == $commit' \
  "$verification_result" >/dev/null \
  || fail 'resultado do verificador da release é divergente'

readonly payload="${extracted}/payload"
readonly deploy_rbac="${payload}/manifests/deployctl/rbac.yaml"
readonly deploy_admission="${payload}/manifests/deployctl/admission.yaml"
readonly secrets_rbac="${payload}/manifests/secretsctl/rbac.yaml"
for sudoers in "${payload}/sudoers/saferwpp-deployctl" \
  "${payload}/sudoers/saferwpp-backupctl" \
  "${payload}/sudoers/saferwpp-secretsctl"; do
  visudo -cf "$sudoers" >/dev/null
done
bash -n "$IDENTITY_CONTROLLER_SOURCE"
systemd-analyze verify "$IDENTITY_SERVICE_SOURCE" "$IDENTITY_TIMER_SOURCE" >/dev/null
promtool check rules "$ALERTS_SOURCE" >/dev/null
[[ -f "$PROMETHEUS_CONFIG" && ! -L "$PROMETHEUS_CONFIG" ]] \
  || fail 'prometheus.yml ausente ou simbólico'

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
readonly backup_directory="${BACKUP_ROOT}/${timestamp}"
install -d -o root -g root -m 0700 "$backup_directory"
readonly backup_manifest="${backup_directory}/targets.tsv"
: >"$backup_manifest"
chmod 0600 "$backup_manifest"
cp --archive --no-dereference "$PROMETHEUS_CONFIG" \
  "${backup_directory}/prometheus.yml"
$K3S kubectl get -f "$deploy_rbac" --ignore-not-found -o yaml \
  >"${backup_directory}/deploy-rbac.yaml"
$K3S kubectl get -f "$secrets_rbac" --ignore-not-found -o yaml \
  >"${backup_directory}/secrets-rbac.yaml"
$K3S kubectl get -f "$deploy_admission" --ignore-not-found -o yaml \
  >"${backup_directory}/deploy-admission.yaml"
timer_was_enabled=false
systemctl is-enabled --quiet saferwpp-kube-identities.timer && timer_was_enabled=true
timer_was_active=false
systemctl is-active --quiet saferwpp-kube-identities.timer && timer_was_active=true

declare -a mappings=(
  "${payload}/bin/saferwpp-deployctl|/usr/local/sbin/saferwpp-deployctl|0755"
  "${payload}/bin/saferwpp-backupctl|/usr/local/sbin/saferwpp-backupctl|0755"
  "${payload}/bin/saferwpp-secretsctl|/usr/local/sbin/saferwpp-secretsctl|0755"
  "${payload}/access/saferwpp-access-session|/usr/local/sbin/saferwpp-access-session|0755"
  "${payload}/config/deployctl/config.json|/etc/saferwpp-deployctl/config.json|0644"
  "${payload}/config/backupctl/config.json|/etc/saferwpp-backupctl/config.json|0644"
  "${payload}/config/secretsctl/config.json|/etc/saferwpp-secretsctl/config.json|0644"
  "${payload}/manifests/deployctl/rbac.yaml|/usr/local/lib/saferwpp-deployctl/rbac.yaml|0644"
  "${payload}/manifests/deployctl/admission.yaml|/usr/local/lib/saferwpp-deployctl/admission.yaml|0644"
  "${payload}/manifests/secretsctl/rbac.yaml|/etc/saferwpp-secretsctl/rbac.yaml|0644"
  "${payload}/sudoers/saferwpp-deployctl|/etc/sudoers.d/saferwpp-deployctl|0440"
  "${payload}/sudoers/saferwpp-backupctl|/etc/sudoers.d/saferwpp-backupctl|0440"
  "${payload}/sudoers/saferwpp-secretsctl|/etc/sudoers.d/saferwpp-secretsctl|0440"
  "${payload}/tmpfiles/saferwpp-deployctl.conf|/etc/tmpfiles.d/saferwpp-deployctl.conf|0644"
  "${payload}/tmpfiles/saferwpp-platformctl.conf|/etc/tmpfiles.d/saferwpp-platformctl.conf|0644"
  "${payload}/tools/node|/usr/local/lib/saferwpp-deployctl/tools/node|0755"
  "${payload}/tools/cosign|/usr/local/lib/saferwpp-deployctl/tools/cosign|0755"
  "${payload}/verify/lab-manifests.mjs|/usr/local/lib/saferwpp-deployctl/verify/lab-manifests.mjs|0644"
  "${payload}/verify/lab-release.mjs|/usr/local/lib/saferwpp-deployctl/verify/lab-release.mjs|0644"
  "${payload}/verify/verify_oci_archive.py|/usr/local/lib/saferwpp-deployctl/verify/verify_oci_archive.py|0644"
  "${verified_public_key}|/etc/saferwpp-deployctl/trust/cosign.pub|0644"
  "${extracted}/control-release.json|/usr/local/lib/saferwpp-deployctl/controller-release/control-release.json|0644"
  "${extracted}/control-release.sig|/usr/local/lib/saferwpp-deployctl/controller-release/control-release.sig|0644"
  "${extracted}/evidence/controllers.spdx.json|/usr/local/lib/saferwpp-deployctl/controller-release/controllers.spdx.json|0644"
  "${extracted}/evidence/controllers.trivy.json|/usr/local/lib/saferwpp-deployctl/controller-release/controllers.trivy.json|0644"
  "${extracted}/evidence/provenance.json|/usr/local/lib/saferwpp-deployctl/controller-release/provenance.json|0644"
  "${IDENTITY_CONTROLLER_SOURCE}|/usr/local/sbin/saferwpp-kube-identityctl|0755"
  "${IDENTITY_SERVICE_SOURCE}|/etc/systemd/system/saferwpp-kube-identities.service|0644"
  "${IDENTITY_TIMER_SOURCE}|/etc/systemd/system/saferwpp-kube-identities.timer|0644"
  "${ALERTS_SOURCE}|${RULES_TARGET}|0640"
)
declare -a kubeconfig_targets=(
  '/etc/rancher/k3s/saferwpp-deployctl.yaml'
  '/etc/rancher/k3s/saferwpp-deployctl.yaml.previous'
  '/etc/rancher/k3s/saferwpp-secretsctl.yaml'
  '/etc/rancher/k3s/saferwpp-secretsctl.yaml.previous'
  '/var/lib/prometheus/node-exporter/saferwpp-kube-identities.prom'
)

backup_target() {
  local target="$1" backup_name
  if [[ -f "$target" && ! -L "$target" ]]; then
    backup_name="$(printf '%s' "$target" | sha256sum | cut -d' ' -f1)"
    cp --archive --no-dereference "$target" "${backup_directory}/${backup_name}"
    printf '%s\t%s\n' "$target" "$backup_name" >>"$backup_manifest"
  elif [[ -e "$target" || -L "$target" ]]; then
    fail "alvo preexistente não é arquivo regular: ${target}"
  else
    printf '%s\t%s\n' "$target" absent >>"$backup_manifest"
  fi
}

for mapping in "${mappings[@]}"; do
  IFS='|' read -r _ target _ <<<"$mapping"
  backup_target "$target"
done
for target in "${kubeconfig_targets[@]}"; do
  backup_target "$target"
done

rollback_needed=true
rollback_bootstrap() {
  local result="$?" target backup_name backup_yaml manifest
  local rollback_failed=false
  trap - EXIT
  set +e
  if [[ "$rollback_needed" == true && "$result" -ne 0 ]]; then
    for manifest in "$deploy_admission" "$secrets_rbac" "$deploy_rbac"; do
      $K3S kubectl delete -f "$manifest" --ignore-not-found >/dev/null 2>&1 \
        || rollback_failed=true
    done
    for backup_yaml in deploy-rbac secrets-rbac deploy-admission; do
      if python3 - "${backup_directory}/${backup_yaml}.yaml" <<'PY'
import sys
import yaml

value = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
raise SystemExit(0 if value.get("items") else 1)
PY
      then
        $K3S kubectl apply -f "${backup_directory}/${backup_yaml}.yaml" \
          >/dev/null 2>&1 || rollback_failed=true
      fi
    done
    while IFS=$'\t' read -r target backup_name; do
      [[ -n "$target" && -n "$backup_name" ]] || continue
      if [[ "$backup_name" == absent ]]; then
        rm -f -- "$target" || rollback_failed=true
      else
        cp --archive --no-dereference \
          "${backup_directory}/${backup_name}" "$target" \
          || rollback_failed=true
      fi
    done <"$backup_manifest"
    cp --archive --no-dereference "${backup_directory}/prometheus.yml" \
      "$PROMETHEUS_CONFIG" || rollback_failed=true
    if [[ "$timer_was_enabled" == false ]]; then
      systemctl disable saferwpp-kube-identities.timer >/dev/null 2>&1 \
        || rollback_failed=true
    fi
    if [[ "$timer_was_active" == false ]]; then
      systemctl stop saferwpp-kube-identities.timer >/dev/null 2>&1 \
        || rollback_failed=true
    fi
    systemctl daemon-reload >/dev/null 2>&1 || rollback_failed=true
    visudo -c >/dev/null 2>&1 || rollback_failed=true
    promtool check config "$PROMETHEUS_CONFIG" >/dev/null 2>&1 \
      || rollback_failed=true
    systemctl reload prometheus.service >/dev/null 2>&1 \
      || rollback_failed=true
    if [[ "$rollback_failed" == true ]]; then
      printf '[bootstrap-saferwpp-controllers] ERRO: rollback incompleto; preserve %s e intervenha antes de nova operação\n' \
        "$backup_directory" >&2
    else
      printf '[bootstrap-saferwpp-controllers] ERRO: instalação revertida de %s\n' \
        "$backup_directory" >&2
    fi
  fi
  remove_work_directory
  exit "$result"
}
trap rollback_bootstrap EXIT

install -d -o root -g root -m 0700 \
  /etc/saferwpp-deployctl /etc/saferwpp-deployctl/trust \
  /etc/saferwpp-backupctl /etc/saferwpp-secretsctl
install -d -o root -g root -m 0755 \
  /usr/local/lib/saferwpp-deployctl \
  /usr/local/lib/saferwpp-deployctl/tools \
  /usr/local/lib/saferwpp-deployctl/verify \
  /usr/local/lib/saferwpp-deployctl/controller-release
install -d -o root -g prometheus -m 0750 /etc/prometheus/rules
for mapping in "${mappings[@]}"; do
  IFS='|' read -r source target mode <<<"$mapping"
  if [[ "$target" == "$RULES_TARGET" ]]; then
    install -D -o root -g prometheus -m "$mode" "$source" "$target"
  else
    install -D -o root -g root -m "$mode" "$source" "$target"
  fi
done
visudo -cf /etc/sudoers.d/saferwpp-deployctl >/dev/null
visudo -cf /etc/sudoers.d/saferwpp-backupctl >/dev/null
visudo -cf /etc/sudoers.d/saferwpp-secretsctl >/dev/null
systemd-tmpfiles --create /etc/tmpfiles.d/saferwpp-deployctl.conf \
  /etc/tmpfiles.d/saferwpp-platformctl.conf

/usr/local/sbin/saferwpp-kube-identityctl ensure
$K3S kubectl apply -f /usr/local/lib/saferwpp-deployctl/rbac.yaml >/dev/null
$K3S kubectl apply -f /etc/saferwpp-secretsctl/rbac.yaml >/dev/null
$K3S kubectl apply -f /usr/local/lib/saferwpp-deployctl/admission.yaml >/dev/null
/usr/local/sbin/saferwpp-kube-identityctl verify

python3 - "$PROMETHEUS_CONFIG" "$RULES_TARGET" <<'PY'
from pathlib import Path
import os
import sys
import yaml

config_path = Path(sys.argv[1])
rule_path = sys.argv[2]
metadata = config_path.stat()
config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
if not isinstance(config, dict):
    raise SystemExit("prometheus.yml não é um mapeamento")
rule_files = config.setdefault("rule_files", [])
if not isinstance(rule_files, list):
    raise SystemExit("rule_files do Prometheus não é uma lista")
if rule_path not in rule_files:
    rule_files.append(rule_path)
temporary = config_path.with_suffix(".yml.saferwpp-controllers.tmp")
temporary.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
temporary.chmod(metadata.st_mode & 0o777)
os.chown(temporary, metadata.st_uid, metadata.st_gid)
temporary.replace(config_path)
PY
promtool check config "$PROMETHEUS_CONFIG" >/dev/null
systemctl daemon-reload
systemctl start --wait saferwpp-kube-identities.service
[[ "$(systemctl show saferwpp-kube-identities.service --property=Result --value)" \
    == success ]] || fail 'reconciliação inicial das identidades falhou'
systemctl enable --now saferwpp-kube-identities.timer >/dev/null
systemctl reload prometheus.service

/usr/local/lib/saferwpp-deployctl/tools/node --version | grep -Fx 'v24.18.0' >/dev/null
/usr/local/lib/saferwpp-deployctl/tools/cosign version \
  | grep -F 'GitVersion:    v2.6.5' >/dev/null
sudo -u apiadmin sudo -n /usr/local/sbin/saferwpp-deployctl \
  contract --output json | jq -e '.status == "passed"' >/dev/null
sudo -u apiadmin sudo -n /usr/local/sbin/saferwpp-backupctl \
  contract --output json | jq -e '.status == "passed"' >/dev/null
sudo -u apiadmin sudo -n /usr/local/sbin/saferwpp-secretsctl \
  contract --output json | jq -e '.status == "passed"' >/dev/null
/usr/local/sbin/apiwpp-deployctl verify >/dev/null \
  || fail 'APIWPP divergiu depois do bootstrap'
/usr/local/sbin/blindou-deployctl verify >/dev/null \
  || fail 'Blindou divergiu depois do bootstrap'
/usr/local/sbin/secondary-slotctl verify >/dev/null \
  || fail 'slot compartilhado divergiu depois do bootstrap'

rollback_needed=false
remove_work_directory
trap - EXIT
printf 'saferwpp_controller_bootstrap=installed release=%s commit=%s backup=%s\n' \
  "$RELEASE_ID" "$GIT_COMMIT" "$backup_directory"
