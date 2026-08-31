#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
umask 077

fail() {
  printf '[bootstrap-dre-validation-executor] ERRO: %s\n' "$*" >&2
  exit 1
}

stage() {
  printf 'dre_validation_executor_bootstrap_stage=%s\n' "$1"
}

if (($# != 2)); then
  fail 'uso interno: bootstrap-dre-validation-executor.sh <commit> <archive-sha256>'
fi
readonly source_commit="$1"
readonly source_archive_sha256="$2"
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || fail 'commit de origem inválido'
[[ "$source_archive_sha256" =~ ^[0-9a-f]{64}$ ]] \
  || fail 'SHA-256 do archive inválido'
stage identity

[[ "$EUID" -eq 0 ]] || fail 'execute como root'
[[ "$(hostname)" == apiwpp ]] || fail 'hostname inesperado'
[[ "$(dpkg --print-architecture)" == amd64 ]] || fail 'arquitetura inesperada'
# shellcheck source=/dev/null
source /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] \
  || fail 'sistema operacional fora do contrato Ubuntu 24.04'

for command in apt-cache apt-get awk comm cut date dpkg-query find getent \
  grep id install mktemp python3 rm rmdir runuser sha256sum sort ss stat \
  systemctl; do
  command -v "$command" >/dev/null || fail "dependência ausente: ${command}"
done
getent passwd apiadmin >/dev/null || fail 'usuário apiadmin ausente'
[[ "$(id -u apiadmin)" -ge 1000 ]] || fail 'UID de apiadmin fora do contrato'
stage host

readonly -a packages=(
  'podman=4.9.3+ds1-1ubuntu0.2'
  'uidmap=1:4.13+dfsg1-4ubuntu3.2'
  'podman-compose=1.0.6-1'
  'slirp4netns=1.2.1-1build2'
  'fuse-overlayfs=1.13-1'
  'passt=0.0~git20240220.1e6f92b-1'
)
readonly -a package_names=(
  podman uidmap podman-compose slirp4netns fuse-overlayfs passt
)
readonly -a forbidden_enabled_units=(
  podman.service
  podman.socket
  podman-auto-update.service
  podman-auto-update.timer
  podman-clean-transient.service
  podman-restart.service
)
readonly state_root='/var/lib/servidor-local/dre-validation-executor'
readonly receipt_path="${state_root}/state.json"

work_directory="$(mktemp -d /run/dre-validation-executor-bootstrap.XXXXXX)"
readonly work_directory
readonly packages_before="${work_directory}/packages-before.txt"
readonly packages_after="${work_directory}/packages-after.txt"
readonly new_packages="${work_directory}/new-packages.txt"
readonly receipt_temporary="${work_directory}/state.json"
readonly policy_rc_d='/usr/sbin/policy-rc.d'
changed=false
complete=false
policy_created=false

installed_package_names() {
  dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' 2>/dev/null |
    awk '$2 ~ /^ii/ {print $1}' | sort -u
}

rollback_new_packages() {
  reconcile_podman_units || return 1
  installed_package_names >"$packages_after"
  comm -13 "$packages_before" "$packages_after" >"$new_packages"
  if [[ ! -s "$new_packages" ]]; then
    return 0
  fi
  local package
  while IFS= read -r package; do
    [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9]+)?$ ]] \
      || fail "pacote inválido no rollback: ${package}"
  done <"$new_packages"
  mapfile -t rollback_packages <"$new_packages"
  DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
    apt-get purge --yes -- "${rollback_packages[@]}" >/dev/null
  reconcile_podman_units || return 1
}

podman_socket_is_listening() {
  ss -H -xl |
    awk 'index($0, "/run/podman/podman.sock") {found=1} END {exit found ? 0 : 1}'
}

reconcile_podman_units() {
  systemctl disable --now "${forbidden_enabled_units[@]}" >/dev/null 2>&1 || true
  systemctl daemon-reload
  systemctl reset-failed "${forbidden_enabled_units[@]}" >/dev/null 2>&1 || true
  if podman_socket_is_listening; then
    printf '[bootstrap-dre-validation-executor] ERRO: socket Podman continua com listener depois da parada fechada\n' >&2
    return 1
  fi
  if [[ -S /run/podman/podman.sock ]]; then
    rm -f -- /run/podman/podman.sock
  fi
  if [[ -d /run/podman ]]; then
    rmdir -- /run/podman 2>/dev/null || true
  fi
}

install_service_start_block() {
  if [[ -e "$policy_rc_d" || -L "$policy_rc_d" ]]; then
    fail 'policy-rc.d preexistente exige decisão operacional separada'
  fi
  printf '#!/bin/sh\nexit 101\n' >"${work_directory}/policy-rc.d"
  install -o root -g root -m 0755 "${work_directory}/policy-rc.d" "$policy_rc_d"
  policy_created=true
}

remove_service_start_block() {
  if [[ "$policy_created" == true ]]; then
    rm -f -- "$policy_rc_d"
    policy_created=false
  fi
}

cleanup() {
  local result="$?"
  trap - EXIT
  if [[ "$result" -ne 0 && "$changed" == true && "$complete" == false ]]; then
    if ! rollback_new_packages; then
      printf '[bootstrap-dre-validation-executor] ERRO: rollback de pacotes falhou\n' >&2
    fi
  fi
  remove_service_start_block
  rm -rf --one-file-system -- "$work_directory"
  exit "$result"
}
trap cleanup EXIT

installed_package_names >"$packages_before"
readonly groups_before="$(id -nG apiadmin)"
readonly subuid_before="$(grep -E '^apiadmin:[0-9]+:[0-9]+$' /etc/subuid || true)"
readonly subgid_before="$(grep -E '^apiadmin:[0-9]+:[0-9]+$' /etc/subgid || true)"
[[ "$subuid_before" == 'apiadmin:100000:65536' ]] \
  || fail 'mapeamento subuid de apiadmin diverge'
[[ "$subgid_before" == 'apiadmin:100000:65536' ]] \
  || fail 'mapeamento subgid de apiadmin diverge'
stage identity-boundary

if ! dpkg-query -W -f='${db:Status-Abbrev}' podman 2>/dev/null |
    awk 'BEGIN {installed=0} /^ii/ {installed=1} END {exit installed ? 0 : 1}'; then
  reconcile_podman_units || fail 'não foi possível reconciliar resíduo Podman anterior'
fi
stage stale-runtime-reconciled

readonly k3s_config_metadata_before="$(
  stat -c '%U:%G:%a:%h' /etc/rancher/k3s/k3s.yaml
)"
[[ "$k3s_config_metadata_before" == root:root:600:1 ]] \
  || fail 'kubeconfig K3s não está root-only'
runuser -u apiadmin -- test ! -r /etc/rancher/k3s/k3s.yaml \
  || fail 'apiadmin já consegue ler o kubeconfig K3s'
if [[ -S /run/k3s/containerd/containerd.sock ]]; then
  runuser -u apiadmin -- test ! -r /run/k3s/containerd/containerd.sock \
    || fail 'apiadmin já consegue acessar o containerd do K3s'
fi
stage k3s-boundary

for unit in "${forbidden_enabled_units[@]}"; do
  [[ "$(systemctl is-active "$unit" 2>/dev/null || true)" != active ]] \
    || fail "unit já estava ativa antes da instalação: ${unit}"
done
[[ ! -S /run/podman/podman.sock ]] \
  || fail 'socket Podman já estava presente antes da instalação'
stage daemon-boundary

DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get update -qq
stage apt-index
for package in "${packages[@]}"; do
  name="${package%%=*}"
  expected="${package#*=}"
  candidate="$(
    apt-cache policy "$name" |
      awk '/Candidate:/ {candidate=$2} END {if (candidate != "") print candidate}'
  )"
  [[ "$candidate" == "$expected" ]] \
    || fail "candidato APT divergente para ${name}: ${candidate:-ausente}"
  installed="$(dpkg-query -W -f='${Version}' "$name" 2>/dev/null || true)"
  [[ -z "$installed" || "$installed" == "$expected" ]] \
    || fail "versão preexistente divergente para ${name}: ${installed}"
done
stage package-candidates

simulation="$(
  DEBIAN_FRONTEND=noninteractive apt-get --simulate --no-remove --no-upgrade \
    install "${packages[@]}"
)"
if grep -Eq '^(Remv|Inst [^ ]+ \[|Conf [^ ]+ \[)' <<<"$simulation"; then
  fail 'a transação APT simulada removeria ou atualizaria pacote existente'
fi
stage apt-simulation

install_service_start_block
stage service-start-block
changed=true
DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
  apt-get install --yes --no-remove --no-upgrade "${packages[@]}"
stage packages-installed
reconcile_podman_units || fail 'não foi possível desabilitar presets Podman'
remove_service_start_block
stage package-presets-disabled

for package in "${packages[@]}"; do
  name="${package%%=*}"
  expected="${package#*=}"
  installed="$(dpkg-query -W -f='${Version}' "$name")"
  [[ "$installed" == "$expected" ]] \
    || fail "versão instalada divergente para ${name}: ${installed}"
done
for command in podman podman-compose newuidmap newgidmap slirp4netns \
  fuse-overlayfs passt pasta buildah; do
  command -v "$command" >/dev/null || fail "ferramenta instalada ausente: ${command}"
done
for helper in /usr/bin/newuidmap /usr/bin/newgidmap; do
  [[ "$(stat -c '%U:%G:%a:%h' "$helper")" == root:root:4755:1 ]] \
    || fail "helper de mapeamento possui metadados inseguros: ${helper}"
done
stage tools

[[ "$(id -nG apiadmin)" == "$groups_before" ]] \
  || fail 'a instalação alterou os grupos de apiadmin'
[[ "$(grep -E '^apiadmin:[0-9]+:[0-9]+$' /etc/subuid || true)" == "$subuid_before" ]] \
  || fail 'a instalação alterou o subuid de apiadmin'
[[ "$(grep -E '^apiadmin:[0-9]+:[0-9]+$' /etc/subgid || true)" == "$subgid_before" ]] \
  || fail 'a instalação alterou o subgid de apiadmin'
[[ "$(stat -c '%U:%G:%a:%h' /etc/rancher/k3s/k3s.yaml)" \
    == "$k3s_config_metadata_before" ]] \
  || fail 'a instalação alterou os metadados do kubeconfig K3s'
runuser -u apiadmin -- test ! -r /etc/rancher/k3s/k3s.yaml \
  || fail 'apiadmin passou a ler o kubeconfig K3s'
if [[ -S /run/k3s/containerd/containerd.sock ]]; then
  runuser -u apiadmin -- test ! -r /run/k3s/containerd/containerd.sock \
    || fail 'apiadmin passou a acessar o containerd do K3s'
fi
stage identity-postcondition

for unit in "${forbidden_enabled_units[@]}"; do
  active_state="$(systemctl is-active "$unit" 2>/dev/null || true)"
  enabled_state="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  [[ "$active_state" != active && "$active_state" != activating ]] \
    || fail "unit Podman ficou ativa: ${unit}"
  case "$enabled_state" in
    enabled|enabled-runtime|linked|linked-runtime|alias)
      fail "unit Podman ficou habilitada: ${unit} (${enabled_state})"
      ;;
  esac
done
[[ ! -S /run/podman/podman.sock ]] || fail 'socket Podman de sistema foi criado'
[[ ! -S "/run/user/$(id -u apiadmin)/podman/podman.sock" ]] \
  || fail 'socket Podman de usuário foi criado'
if [[ -d /etc/systemd/system ]]; then
  [[ -z "$(find /etc/systemd/system -type l -iname '*podman*' -print -quit)" ]] \
    || fail 'Podman recebeu ativação persistente no systemd'
fi
if [[ -d /home/apiadmin/.config/systemd/user ]]; then
  [[ -z "$(find /home/apiadmin/.config/systemd/user -type l -iname '*podman*' -print -quit)" ]] \
    || fail 'Podman recebeu ativação persistente no systemd do usuário'
fi
stage daemon-postcondition

installed_package_names >"$packages_after"
comm -13 "$packages_before" "$packages_after" >"$new_packages"
install -d -o root -g root -m 0700 "$state_root"
python3 - "$receipt_temporary" "$source_commit" "$source_archive_sha256" \
  "$groups_before" "$new_packages" "${packages[@]}" <<'PY'
from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
import subprocess
import sys

target = Path(sys.argv[1])
commit = sys.argv[2]
archive_sha256 = sys.argv[3]
groups = sys.argv[4].split()
new_packages = Path(sys.argv[5]).read_text(encoding="utf-8").splitlines()
requested = sys.argv[6:]
versions = {}
for item in requested:
    name, expected = item.split("=", 1)
    observed = subprocess.run(
        ["dpkg-query", "-W", "-f=${Version}", name],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout
    if observed != expected:
        raise SystemExit(f"versão divergente durante o recibo: {name}")
    versions[name] = observed
payload = {
    "schema": 1,
    "installed_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
    "source_commit": commit,
    "source_archive_sha256": archive_sha256,
    "packages": versions,
    "new_packages": new_packages,
    "apiadmin_groups": groups,
    "rootless": True,
    "persistent_daemon": False,
    "k3s_access_granted": False,
}
target.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
install -o root -g root -m 0600 "$receipt_temporary" "$receipt_path"
stage receipt

complete=true
printf 'dre_validation_executor_bootstrap=passed rootless=true daemon=false k3s_access=false'
for name in "${package_names[@]}"; do
  printf ' %s=%s' "$name" "$(dpkg-query -W -f='${Version}' "$name")"
done
printf '\n'
