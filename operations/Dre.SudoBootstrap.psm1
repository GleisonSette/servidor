Set-StrictMode -Version Latest

function Read-DreSudoPassword {
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

function New-DreRootBootstrapScript {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteRoot,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedArchiveSha256,

        [Parameter(Mandatory = $true)]
        [string]$PublicKeySha256
    )

    $template = @'
set -Eeuo pipefail
readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
umask 077

fail() {
  printf '[dre-root-bootstrap] ERRO: %s\n' "$*" >&2
  exit 1
}

readonly source_archive='__REMOTE_ROOT__/bundle.tar.gz'
readonly source_public_key='__REMOTE_ROOT__/release-signing.pub'
readonly expected_archive_sha256='__ARCHIVE_SHA256__'
readonly public_key_sha256='__PUBLIC_KEY_SHA256__'
readonly release_root='/var/lib/servidor-local/bootstrap-releases/dre-controller'
readonly release_directory="${release_root}/${expected_archive_sha256}"
readonly bootstrap_lock='/run/lock/servidor-local-platform-bootstrap.lock'

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'
[[ "$(hostname)" == apiwpp ]] || fail 'hostname inesperado'
for command in base64 chmod chown cut find flock install mktemp mv python3 rm \
  sha256sum stat systemctl; do
  command -v "$command" >/dev/null || fail "dependência ausente: ${command}"
done
for source in "$source_archive" "$source_public_key"; do
  [[ -f "$source" && ! -L "$source" ]] || fail "fonte ausente ou simbólica: ${source}"
  [[ "$(stat -c '%U:%G:%a:%h' "$source")" == 'apiadmin:apiadmin:600:1' ]] \
    || fail "fonte possui ownership, modo ou links inseguros: ${source}"
done
[[ "$(sha256sum "$source_archive" | cut -d' ' -f1)" == "$expected_archive_sha256" ]] \
  || fail 'SHA-256 do bundle transportado diverge'
[[ "$(sha256sum "$source_public_key" | cut -d' ' -f1)" == "$public_key_sha256" ]] \
  || fail 'SHA-256 da chave pública transportada diverge'

install -d -o root -g root -m 0700 "$release_root"
exec 9>"$bootstrap_lock"
chmod 0600 "$bootstrap_lock"
flock -n 9 || fail 'outro bootstrap de plataforma está em andamento'

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
  [[ -f "${release_directory}/bundle.tar.gz" \
      && ! -L "${release_directory}/bundle.tar.gz" \
      && -f "${release_directory}/release-signing.pub" \
      && ! -L "${release_directory}/release-signing.pub" ]] \
    || fail 'artefatos do cache root-owned são inválidos'
  [[ "$(sha256sum "${release_directory}/bundle.tar.gz" | cut -d' ' -f1)" \
      == "$expected_archive_sha256" ]] || fail 'bundle do cache root-owned diverge'
  [[ "$(sha256sum "${release_directory}/release-signing.pub" | cut -d' ' -f1)" \
      == "$public_key_sha256" ]] || fail 'chave pública do cache root-owned diverge'
else
  work_directory="$(mktemp -d "${release_root}/.${expected_archive_sha256}.XXXXXX")"
  install -o root -g root -m 0600 -- "$source_archive" \
    "${work_directory}/bundle.tar.gz"
  install -o root -g root -m 0600 -- "$source_public_key" \
    "${work_directory}/release-signing.pub"
  install -d -o root -g root -m 0700 "${work_directory}/repository"
  python3 - "${work_directory}/bundle.tar.gz" \
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
    "operations/Dre.SudoBootstrap.psm1",
    "operations/remote/bootstrap-dre-deployctl.sh",
    "operations/remote/dre-controller-metrics.service",
    "operations/remote/dre-controller-metrics.timer",
    "operations/remote/dre-deployctl",
    "operations/remote/dre-deployctl.logrotate",
    "operations/remote/dre-deployctl.sudoers",
    "operations/remote/dre-kube-identity.service",
    "operations/remote/dre-kube-identity.timer",
    "operations/remote/dre-kube-identityctl",
    "operations/remote/dre-release-verify.py",
    "operations/remote/dre-restore-render.py",
    "operations/remote/dre-secret-material.py",
    "operations/remote/dre-validation-material.py",
    "operations/remote/verify-dre-controller-artifacts.py",
    "platform/dre/controller-foundation.yaml",
    "platform/dre/validation-access.yaml",
    "platform/dre/monitoring/prometheus-alerts.yaml",
}
maximum_members = 48
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
        descriptor = os.open(target, flags, 0o644)
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

flock --unlock 9
exec 9>&-

readonly repository="${release_directory}/repository"
readonly verifier="${repository}/operations/remote/verify-dre-controller-artifacts.py"
readonly bootstrap="${repository}/operations/remote/bootstrap-dre-deployctl.sh"
for source in "$verifier" "$bootstrap"; do
  [[ -f "$source" && ! -L "$source" \
      && "$(stat -c '%U:%G:%h' "$source")" == 'root:root:1' ]] \
    || fail "fonte root-owned inválida: ${source}"
done
cd "$repository"
python3 "$verifier"
/bin/bash -n "$bootstrap"
/bin/bash "$bootstrap" "${release_directory}/release-signing.pub" "$public_key_sha256"
printf 'dre_root_bootstrap=passed archive_sha256=%s public_key_sha256=%s\n' \
  "$expected_archive_sha256" "$public_key_sha256"
'@
    $script = $template.Replace('__REMOTE_ROOT__', $RemoteRoot)
    $script = $script.Replace('__ARCHIVE_SHA256__', $ExpectedArchiveSha256)
    $script = $script.Replace('__PUBLIC_KEY_SHA256__', $PublicKeySha256)
    return $script.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Invoke-DreSudoBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SshArguments,

        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$RemoteRoot,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedArchiveSha256,

        [Parameter(Mandatory = $true)]
        [string]$PublicKeySha256
    )

    if ($Server -cne 'apiadmin@192.168.100.59') {
        throw 'O bootstrap DRE aceita somente o servidor físico aprovado.'
    }
    if ($ExpectedArchiveSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $PublicKeySha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'SHA-256 inválido para o bootstrap DRE.'
    }
    $keyPrefix = $PublicKeySha256.Substring(0, 12)
    $expectedRootPattern =
        '^/home/apiadmin/dre-controller-bootstrap-' +
        [Regex]::Escape($keyPrefix) + '-[0-9]{8}T[0-9]{6}Z$'
    if ($RemoteRoot -cnotmatch $expectedRootPattern) {
        throw 'Diretório remoto fora do staging fechado do DRE.'
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

    $rootScript = New-DreRootBootstrapScript `
        -RemoteRoot $RemoteRoot `
        -ExpectedArchiveSha256 $ExpectedArchiveSha256 `
        -PublicKeySha256 $PublicKeySha256
    $encodedScript = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes($rootScript)
    )
    $remoteCommand =
        "sudo -S -p '' -- /bin/bash -c `"printf '%s' '$encodedScript' | " +
        "base64 --decode | /bin/bash`""

    $envFile = 'C:\github\servidor\.env'
    $password = Read-DreSudoPassword -EnvFile $envFile
    try {
        $password | & ssh.exe @SshArguments $Server $remoteCommand
        if ($LASTEXITCODE -ne 0) {
            throw 'Bootstrap remoto autenticado do DRE falhou.'
        }
    }
    finally {
        $password = $null
        $rootScript = $null
        $encodedScript = $null
        $remoteCommand = $null
    }
}

Export-ModuleMember -Function Invoke-DreSudoBootstrap
