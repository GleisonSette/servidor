Set-StrictMode -Version Latest

function Read-SecondarySlotSudoPassword {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvFile
    )

    $fullPath = [IO.Path]::GetFullPath($EnvFile)
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'O arquivo administrativo deve ser regular e não simbólico.'
    }
    if ($item.Length -gt 65536) {
        throw 'O arquivo administrativo excede o limite de 64 KiB.'
    }

    $password = $null
    $matchCount = 0
    $lines = [IO.File]::ReadLines($fullPath).GetEnumerator()
    try {
        while ($lines.MoveNext()) {
            $line = [string]$lines.Current
            if ($line.StartsWith('KEY_SERVIDOR=', [StringComparison]::Ordinal)) {
                $matchCount++
                $password = $line.Substring('KEY_SERVIDOR='.Length)
            }
        }
    }
    finally {
        $lines.Dispose()
    }

    if ($matchCount -ne 1) {
        throw 'O arquivo administrativo deve conter exatamente uma chave KEY_SERVIDOR.'
    }
    if ([string]::IsNullOrEmpty($password) -or $password.Length -gt 1024 -or
        $password.IndexOf([char]0) -ge 0 -or
        $password.Contains("`r") -or $password.Contains("`n")) {
        throw 'KEY_SERVIDOR está vazia ou possui formato inválido.'
    }

    return $password
}

function New-SecondarySlotRootBootstrapScript {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteArchive,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSha256,

        [Parameter(Mandatory = $true)]
        [string]$GitCommit
    )

    $template = @'
set -Eeuo pipefail
readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
umask 077

fail() {
  printf '[secondary-slot-root-bootstrap] ERRO: %s\n' "$*" >&2
  exit 1
}

readonly source_archive='__REMOTE_ARCHIVE__'
readonly expected_sha256='__EXPECTED_SHA256__'
readonly git_commit='__GIT_COMMIT__'
readonly release_root='/var/lib/servidor-local/bootstrap-releases/secondary-slot'
readonly release_directory="${release_root}/${git_commit}"
readonly bootstrap_lock='/run/lock/servidor-local-platform-bootstrap.lock'

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'
[[ "$(hostname)" == apiwpp ]] || fail 'hostname inesperado'
for command in chmod chown cut find flock install mktemp mv python3 rm sha256sum stat; do
  command -v "$command" >/dev/null || fail "dependência ausente: ${command}"
done
[[ -f "$source_archive" && ! -L "$source_archive" ]] \
  || fail 'arquivo transportado ausente ou simbólico'
[[ "$(stat -c '%U:%G:%a:%h' "$source_archive")" == 'apiadmin:apiadmin:600:1' ]] \
  || fail 'arquivo transportado possui ownership, modo ou links inseguros'

install -d -o root -g root -m 0700 "$release_root"
exec 9>"$bootstrap_lock"
chmod 0600 "$bootstrap_lock"
flock -n 9 || fail 'outro bootstrap de plataforma está em andamento'

/usr/local/sbin/apiwpp-deployctl verify >/dev/null
/usr/local/sbin/blindou-hostctl verify >/dev/null
/usr/local/sbin/blindou-deployctl status >/dev/null

work_directory=''
cleanup() {
  local result="$?"
  trap - EXIT
  if [[ -n "$work_directory" && -d "$work_directory" ]]; then
    rm -rf --one-file-system -- "$work_directory"
  fi
  exit "$result"
}
trap cleanup EXIT

if [[ -e "$release_directory" || -L "$release_directory" ]]; then
  [[ -d "$release_directory" && ! -L "$release_directory" ]] \
    || fail 'cache root-owned preexistente é inválido'
  [[ -f "${release_directory}/release.tar.gz" \
      && ! -L "${release_directory}/release.tar.gz" ]] \
    || fail 'arquivo do cache root-owned é inválido'
  actual_sha256="$(sha256sum "${release_directory}/release.tar.gz" | cut -d' ' -f1)"
  [[ "$actual_sha256" == "$expected_sha256" ]] \
    || fail 'SHA-256 do cache root-owned diverge'
else
  work_directory="$(mktemp -d "${release_root}/.${git_commit}.XXXXXX")"
  install -o root -g root -m 0600 -- "$source_archive" \
    "${work_directory}/release.tar.gz"
  actual_sha256="$(sha256sum "${work_directory}/release.tar.gz" | cut -d' ' -f1)"
  [[ "$actual_sha256" == "$expected_sha256" ]] \
    || fail 'SHA-256 do snapshot root-owned diverge'
  install -d -o root -g root -m 0700 "${work_directory}/repository"
  python3 - "${work_directory}/release.tar.gz" \
    "${work_directory}/repository" <<'PY'
from __future__ import annotations

import os
from pathlib import Path, PurePosixPath
import stat
import sys
import tarfile

archive = Path(sys.argv[1])
destination = Path(sys.argv[2]).resolve()
allowed_files = {
    "operations/Invoke-SecondarySlotBootstrap.ps1",
    "operations/SecondarySlot.SudoBootstrap.psm1",
    "operations/remote/bootstrap-secondary-slotctl.sh",
    "operations/remote/secondary-slotctl",
    "operations/remote/secondary-slotctl.sudoers",
    "operations/remote/secondary-slot-metrics.service",
    "operations/remote/secondary-slot-metrics.timer",
    "operations/remote/secondary-slot-tmpfiles.conf",
    "operations/remote/secondary_slot.py",
    "operations/remote/test-secondary-slot.py",
    "operations/remote/verify-secondary-slot-artifacts.py",
    "platform/base/namespaces.yaml",
    "platform/saferwpp/00-platform-namespaces.yaml",
    "platform/secondary-slot/admission.yaml",
    "platform/secondary-slot/contract.yaml",
    "platform/secondary-slot/kustomization.yaml",
    "platform/secondary-slot/monitoring/prometheus-alerts.yaml",
    "runbooks/secondary-slot.md",
}
maximum_members = 64
maximum_file_bytes = 8 * 1024 * 1024
maximum_total_bytes = 32 * 1024 * 1024


def validated_name(raw_name: str) -> str:
    path = PurePosixPath(raw_name)
    normalized = str(path)
    if (
        not raw_name
        or path.is_absolute()
        or normalized != raw_name.rstrip("/")
        or any(part in {"", ".", ".."} for part in path.parts)
    ):
        raise SystemExit(f"membro inválido no arquivo: {raw_name!r}")
    return normalized


with tarfile.open(archive, mode="r:gz") as release:
    members = release.getmembers()
    if not members or len(members) > maximum_members:
        raise SystemExit("quantidade de membros do arquivo é inválida")
    total_bytes = 0
    regular_files: list[tuple[tarfile.TarInfo, str]] = []
    for member in members:
        name = validated_name(member.name)
        if member.isdir():
            prefix = f"{name}/"
            if not any(candidate.startswith(prefix) for candidate in allowed_files):
                raise SystemExit(f"diretório inesperado no arquivo: {name}")
            continue
        if not member.isreg() or name not in allowed_files:
            raise SystemExit(f"membro inesperado no arquivo: {name}")
        if member.size < 0 or member.size > maximum_file_bytes:
            raise SystemExit(f"tamanho inválido no arquivo: {name}")
        total_bytes += member.size
        if total_bytes > maximum_total_bytes:
            raise SystemExit("arquivo excede o limite total descompactado")
        regular_files.append((member, name))
    if {name for _, name in regular_files} != allowed_files:
        raise SystemExit("inventário do arquivo diverge do contrato fechado")

    for member, name in regular_files:
        target = destination.joinpath(*PurePosixPath(name).parts)
        target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
        source = release.extractfile(member)
        if source is None:
            raise SystemExit(f"não foi possível abrir membro regular: {name}")
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
        flags |= getattr(os, "O_NOFOLLOW", 0)
        mode = 0o755 if member.mode & 0o111 else 0o644
        descriptor = os.open(target, flags, mode)
        try:
            with source:
                while chunk := source.read(1024 * 1024):
                    view = memoryview(chunk)
                    while view:
                        written = os.write(descriptor, view)
                        if written <= 0:
                            raise SystemExit(f"gravação interrompida: {name}")
                        view = view[written:]
            os.fsync(descriptor)
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                raise SystemExit(f"alvo extraído possui tipo inseguro: {name}")
        finally:
            os.close(descriptor)
PY
  chown -R root:root "$work_directory"
  [[ -z "$(find "${work_directory}/repository" -type l -print -quit)" ]] \
    || fail 'release contém link simbólico'
  mv -- "$work_directory" "$release_directory"
  work_directory=''
fi

readonly repository="${release_directory}/repository"
readonly verifier="${repository}/operations/remote/verify-secondary-slot-artifacts.py"
readonly bootstrap="${repository}/operations/remote/bootstrap-secondary-slotctl.sh"
for source in "$verifier" "$bootstrap"; do
  [[ -f "$source" && ! -L "$source" \
      && "$(stat -c '%U:%G:%h' "$source")" == 'root:root:1' ]] \
    || fail "fonte root-owned inválida: ${source}"
done
python3 "$verifier"
/bin/bash -n "$bootstrap"
"$bootstrap"
printf 'secondary_slot_root_bootstrap=passed commit=%s sha256=%s\n' \
  "$git_commit" "$expected_sha256"
'@
    $script = $template.Replace('__REMOTE_ARCHIVE__', $RemoteArchive)
    $script = $script.Replace('__EXPECTED_SHA256__', $ExpectedSha256)
    $script = $script.Replace('__GIT_COMMIT__', $GitCommit)
    return $script
}

function Invoke-SecondarySlotSudoBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SshArguments,

        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$RemoteArchive,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSha256,

        [Parameter(Mandatory = $true)]
        [string]$GitCommit
    )

    if ($Server -cne 'apiadmin@192.168.100.59') {
        throw 'O bootstrap aceita somente o servidor físico aprovado.'
    }
    if ($GitCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Commit Git inválido para o bootstrap.'
    }
    if ($ExpectedSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'SHA-256 inválido para o bootstrap.'
    }
    $shortCommit = $GitCommit.Substring(0, 12)
    $expectedRemoteArchive =
        "/home/apiadmin/saferwpp-secondary-slot-bootstrap-$shortCommit/" +
        "servidor-secondary-slot-$shortCommit.tar.gz"
    if ($RemoteArchive -cne $expectedRemoteArchive) {
        throw 'Arquivo remoto fora do staging fechado do slot secundário.'
    }
    foreach ($requiredOption in @(
        'IdentitiesOnly=yes',
        'BatchMode=yes',
        'StrictHostKeyChecking=yes'
    )) {
        if ($SshArguments -notcontains $requiredOption) {
            throw "Opção SSH obrigatória ausente: $requiredOption"
        }
    }

    $rootScript = New-SecondarySlotRootBootstrapScript `
        -RemoteArchive $RemoteArchive `
        -ExpectedSha256 $ExpectedSha256 `
        -GitCommit $GitCommit
    $encodedScript = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes($rootScript)
    )
    $remoteCommand =
        "sudo -S -p '' -- /bin/bash -c `"printf '%s' '$encodedScript' | " +
        "base64 --decode | /bin/bash`""

    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $envFile = Join-Path $repositoryRoot '.env'
    $password = Read-SecondarySlotSudoPassword -EnvFile $envFile
    try {
        $password | & ssh.exe @SshArguments $Server $remoteCommand
        if ($LASTEXITCODE -ne 0) {
            throw 'Bootstrap remoto autenticado do slot secundário falhou.'
        }
    }
    finally {
        $password = $null
        $rootScript = $null
        $encodedScript = $null
        $remoteCommand = $null
    }
}

Export-ModuleMember -Function Invoke-SecondarySlotSudoBootstrap
