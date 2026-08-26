#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
umask 077

readonly EXPECTED_HOSTNAME='apiwpp'
readonly SOURCE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SOURCE_DIRECTORY}/../.." && pwd)"
readonly CONTROLLER_SOURCE="${SOURCE_DIRECTORY}/secondary-slotctl"
readonly LIBRARY_SOURCE="${SOURCE_DIRECTORY}/secondary_slot.py"
readonly SUDOERS_SOURCE="${SOURCE_DIRECTORY}/secondary-slotctl.sudoers"
readonly SERVICE_SOURCE="${SOURCE_DIRECTORY}/secondary-slot-metrics.service"
readonly TIMER_SOURCE="${SOURCE_DIRECTORY}/secondary-slot-metrics.timer"
readonly TMPFILES_SOURCE="${SOURCE_DIRECTORY}/secondary-slot-tmpfiles.conf"
readonly CONTRACT_SOURCE="${REPOSITORY_ROOT}/platform/secondary-slot/contract.yaml"
readonly ADMISSION_SOURCE="${REPOSITORY_ROOT}/platform/secondary-slot/admission.yaml"
readonly ALERTS_SOURCE="${REPOSITORY_ROOT}/platform/secondary-slot/monitoring/prometheus-alerts.yaml"
readonly VERIFIER_SOURCE="${SOURCE_DIRECTORY}/verify-secondary-slot-artifacts.py"
readonly CONTROLLER_TARGET='/usr/local/sbin/secondary-slotctl'
readonly LIBRARY_TARGET='/usr/local/lib/servidor-local/secondary-slot'
readonly SUDOERS_TARGET='/etc/sudoers.d/secondary-slotctl'
readonly RULES_TARGET='/etc/prometheus/rules/secondary-slot.yml'
readonly PROMETHEUS_CONFIG='/etc/prometheus/prometheus.yml'
readonly TMPFILES_TARGET='/etc/tmpfiles.d/secondary-slot.conf'
readonly BACKUP_ROOT='/var/backups/servidor-local/secondary-slot-bootstrap'

fail() {
  printf '[bootstrap-secondary-slotctl] ERRO: %s\n' "$*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'
[[ "$(hostname)" == "$EXPECTED_HOSTNAME" ]] || fail 'hostname inesperado'
for command in python3 visudo promtool systemd-analyze systemd-tmpfiles k3s install cp diff sha256sum sudo systemctl; do
  command -v "$command" >/dev/null || fail "dependência ausente: ${command}"
done
for source in \
  "$CONTROLLER_SOURCE" "$LIBRARY_SOURCE" "$SUDOERS_SOURCE" \
  "$SERVICE_SOURCE" "$TIMER_SOURCE" "$CONTRACT_SOURCE" \
  "$TMPFILES_SOURCE" "$ADMISSION_SOURCE" "$ALERTS_SOURCE" "$VERIFIER_SOURCE"; do
  [[ -f "$source" && ! -L "$source" ]] || fail "fonte ausente ou simbólica: ${source}"
done

python3 "$VERIFIER_SOURCE"
visudo -cf "$SUDOERS_SOURCE" >/dev/null
promtool check rules "$ALERTS_SOURCE" >/dev/null

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_directory="${BACKUP_ROOT}/${timestamp}"
install -d -o root -g root -m 0700 "$backup_directory"
backup_manifest="${backup_directory}/targets.tsv"
: >"$backup_manifest"
chmod 0600 "$backup_manifest"
timer_was_enabled=false
systemctl is-enabled --quiet secondary-slot-metrics.timer && timer_was_enabled=true
timer_was_active=false
systemctl is-active --quiet secondary-slot-metrics.timer && timer_was_active=true
lock_was_present=false
if [[ -e /run/lock/servidor-local-secondary-slot.lock \
    || -L /run/lock/servidor-local-secondary-slot.lock ]]; then
  [[ -f /run/lock/servidor-local-secondary-slot.lock \
      && ! -L /run/lock/servidor-local-secondary-slot.lock \
      && "$(stat -c '%U:%G:%a:%h' /run/lock/servidor-local-secondary-slot.lock)" \
        == 'root:root:600:1' ]] \
    || fail 'lock global preexistente é inseguro'
  lock_was_present=true
fi
rollback_needed=false

rollback_bootstrap() {
  local result="$?" target backup_name
  trap - EXIT
  if [[ "$rollback_needed" == true && "$result" -ne 0 ]]; then
    while IFS=$'\t' read -r target backup_name; do
      [[ -n "$target" && -n "$backup_name" ]] || continue
      if [[ "$backup_name" == absent ]]; then
        rm -f -- "$target"
      else
        cp --archive --no-dereference \
          "${backup_directory}/${backup_name}" "$target"
      fi
    done <"$backup_manifest"
    cp --archive --no-dereference \
      "${backup_directory}/prometheus.yml" "$PROMETHEUS_CONFIG"
    if [[ "$timer_was_enabled" == false ]]; then
      systemctl disable secondary-slot-metrics.timer >/dev/null 2>&1 || true
    fi
    if [[ "$timer_was_active" == false ]]; then
      systemctl stop secondary-slot-metrics.timer >/dev/null 2>&1 || true
    fi
    if [[ "$lock_was_present" == false ]]; then
      rm -f -- /run/lock/servidor-local-secondary-slot.lock
    fi
    systemctl daemon-reload >/dev/null 2>&1 || true
    visudo -cf "$SUDOERS_TARGET" >/dev/null 2>&1 || true
    promtool check config "$PROMETHEUS_CONFIG" >/dev/null 2>&1 \
      && systemctl reload prometheus.service >/dev/null 2>&1 || true
    printf '[bootstrap-secondary-slotctl] ERRO: instalação revertida de %s\n' \
      "$backup_directory" >&2
  fi
  exit "$result"
}

for target in \
  "$CONTROLLER_TARGET" "${LIBRARY_TARGET}/secondary_slot.py" \
  "${LIBRARY_TARGET}/contract.yaml" "${LIBRARY_TARGET}/admission.yaml" \
  "$SUDOERS_TARGET" "$RULES_TARGET" \
  "$TMPFILES_TARGET" \
  /etc/systemd/system/secondary-slot-metrics.service \
  /etc/systemd/system/secondary-slot-metrics.timer; do
  if [[ -f "$target" && ! -L "$target" ]]; then
    backup_name="$(printf '%s' "$target" | sha256sum | cut -d' ' -f1)"
    cp --archive --no-dereference "$target" "${backup_directory}/${backup_name}"
    printf '%s\t%s\n' "$target" "$backup_name" >>"$backup_manifest"
  elif [[ -e "$target" || -L "$target" ]]; then
    fail "alvo preexistente não é arquivo regular: ${target}"
  else
    printf '%s\t%s\n' "$target" absent >>"$backup_manifest"
  fi
done
[[ -f "$PROMETHEUS_CONFIG" && ! -L "$PROMETHEUS_CONFIG" ]] \
  || fail 'configuração Prometheus ausente ou simbólica'
cp --archive --no-dereference "$PROMETHEUS_CONFIG" \
  "${backup_directory}/prometheus.yml"
rollback_needed=true
trap rollback_bootstrap EXIT

install -d -o root -g root -m 0755 "$LIBRARY_TARGET"
install -d -o root -g prometheus -m 0750 /etc/prometheus/rules
install -d -o root -g root -m 0700 /var/lib/servidor-local/secondary-slot
if [[ ! -e /var/log/servidor-local ]]; then
  install -d -o root -g root -m 0700 /var/log/servidor-local
fi
[[ -d /var/log/servidor-local && ! -L /var/log/servidor-local \
    && "$(stat -c '%U' /var/log/servidor-local)" == root ]] \
  || fail 'diretório compartilhado de logs é inseguro'
install -d -o root -g root -m 0700 /var/log/servidor-local/secondary-slot
install -o root -g root -m 0755 "$CONTROLLER_SOURCE" "$CONTROLLER_TARGET"
install -o root -g root -m 0644 "$LIBRARY_SOURCE" "${LIBRARY_TARGET}/secondary_slot.py"
install -o root -g root -m 0644 "$CONTRACT_SOURCE" "${LIBRARY_TARGET}/contract.yaml"
install -o root -g root -m 0644 "$ADMISSION_SOURCE" "${LIBRARY_TARGET}/admission.yaml"
install -o root -g root -m 0440 "$SUDOERS_SOURCE" "$SUDOERS_TARGET"
install -o root -g prometheus -m 0640 "$ALERTS_SOURCE" "$RULES_TARGET"
install -o root -g root -m 0644 "$SERVICE_SOURCE" \
  /etc/systemd/system/secondary-slot-metrics.service
install -o root -g root -m 0644 "$TIMER_SOURCE" \
  /etc/systemd/system/secondary-slot-metrics.timer
install -o root -g root -m 0644 "$TMPFILES_SOURCE" "$TMPFILES_TARGET"
systemd-tmpfiles --create "$TMPFILES_TARGET"
[[ -f /run/lock/servidor-local-secondary-slot.lock \
    && ! -L /run/lock/servidor-local-secondary-slot.lock \
    && "$(stat -c '%U:%G:%a:%h' /run/lock/servidor-local-secondary-slot.lock)" \
      == 'root:root:600:1' ]] \
  || fail 'lock global não ficou root-only e regular'
systemd-analyze verify \
  /etc/systemd/system/secondary-slot-metrics.service \
  /etc/systemd/system/secondary-slot-metrics.timer >/dev/null

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
temporary = config_path.with_suffix(".yml.secondary-slot.tmp")
temporary.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
temporary.chmod(metadata.st_mode & 0o777)
os.chown(temporary, metadata.st_uid, metadata.st_gid)
temporary.replace(config_path)
PY

visudo -cf "$SUDOERS_TARGET" >/dev/null
promtool check config "$PROMETHEUS_CONFIG" >/dev/null
systemctl daemon-reload
systemctl start --wait secondary-slot-metrics.service
[[ "$(systemctl show secondary-slot-metrics.service --property=Result --value)" \
    == success ]] || fail 'coleta inicial de métricas falhou'
systemctl enable --now secondary-slot-metrics.timer >/dev/null
systemctl reload prometheus.service
sudo -u apiadmin sudo -n "$CONTROLLER_TARGET" status >/dev/null
rollback_needed=false
printf 'secondary_slotctl_bootstrap=installed backup=%s\n' "$backup_directory"
