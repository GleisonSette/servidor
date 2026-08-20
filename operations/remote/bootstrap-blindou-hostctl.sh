#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
umask 077

readonly EXPECTED_HOSTNAME='apiwpp'
readonly SOURCE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONTROLLER_SOURCE="${SOURCE_DIRECTORY}/blindou-hostctl"
readonly SUDOERS_SOURCE="${SOURCE_DIRECTORY}/blindou-hostctl.sudoers"
readonly CONTROLLER_TARGET='/usr/local/sbin/blindou-hostctl'
readonly SUDOERS_TARGET='/etc/sudoers.d/blindou-hostctl'

[[ "${EUID}" -eq 0 ]] || { printf '%s\n' 'execute como root' >&2; exit 1; }
[[ "$(hostname)" == "$EXPECTED_HOSTNAME" ]] \
  || { printf '%s\n' 'hostname inesperado' >&2; exit 1; }
[[ -f "$CONTROLLER_SOURCE" && ! -L "$CONTROLLER_SOURCE" ]] \
  || { printf '%s\n' 'fonte do controlador ausente ou inválida' >&2; exit 1; }
[[ -f "$SUDOERS_SOURCE" && ! -L "$SUDOERS_SOURCE" ]] \
  || { printf '%s\n' 'política sudoers ausente ou inválida' >&2; exit 1; }
bash -n "$CONTROLLER_SOURCE"
visudo -cf "$SUDOERS_SOURCE" >/dev/null

install -o root -g root -m 0755 "$CONTROLLER_SOURCE" "$CONTROLLER_TARGET"
install -o root -g root -m 0440 "$SUDOERS_SOURCE" "$SUDOERS_TARGET"
visudo -cf "$SUDOERS_TARGET" >/dev/null

sudo -u apiadmin sudo -n "$CONTROLLER_TARGET" status >/dev/null
printf '%s\n' 'blindou_hostctl_bootstrap=installed'
