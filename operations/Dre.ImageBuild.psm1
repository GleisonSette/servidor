Set-StrictMode -Version Latest

function Read-DreImageBuildSudoPassword {
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

function New-DreImageBuildRootWrapper {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteRoot,

        [Parameter(Mandatory = $true)]
        [string]$SourceRevision,

        [Parameter(Mandatory = $true)]
        [string]$SourceArchiveSha256,

        [Parameter(Mandatory = $true)]
        [string]$BuildKitArchiveSha256,

        [Parameter(Mandatory = $true)]
        [string]$BuildScriptSha256
    )

    $template = @'
set -Eeuo pipefail
readonly PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
umask 077

fail() {
  printf '[dre-image-build-wrapper] ERRO: %s\n' "$*" >&2
  exit 1
}

readonly remote_root='__REMOTE_ROOT__'
readonly source_script="${remote_root}/build-dre-images.sh"
readonly expected_script_sha256='__BUILD_SCRIPT_SHA256__'
readonly source_revision='__SOURCE_REVISION__'
readonly source_archive_sha256='__SOURCE_ARCHIVE_SHA256__'
readonly buildkit_archive_sha256='__BUILDKIT_ARCHIVE_SHA256__'

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'
[[ "$(hostname)" == apiwpp ]] || fail 'hostname inesperado'
for command in chmod cut install mktemp rm sha256sum stat; do
  command -v "$command" >/dev/null || fail "dependência ausente: ${command}"
done
[[ -f "$source_script" && ! -L "$source_script" ]] \
  || fail 'script de build ausente ou simbólico'
[[ "$(stat -c '%U:%G:%a:%h' "$source_script")" == 'apiadmin:apiadmin:600:1' ]] \
  || fail 'script de build possui ownership, modo ou links inseguros'
[[ "$(sha256sum "$source_script" | cut -d' ' -f1)" == "$expected_script_sha256" ]] \
  || fail 'SHA-256 do script de build diverge'

work_directory="$(mktemp -d /var/tmp/dre-image-build-wrapper.XXXXXX)"
cleanup() {
  local result="$?"
  trap - EXIT
  if [[ -n "$work_directory" && -d "$work_directory" \
      && "$work_directory" == /var/tmp/dre-image-build-wrapper.* ]]; then
    rm -rf --one-file-system -- "$work_directory"
  fi
  exit "$result"
}
trap cleanup EXIT
install -o root -g root -m 0500 -- "$source_script" \
  "${work_directory}/build-dre-images.sh"
[[ "$(sha256sum "${work_directory}/build-dre-images.sh" | cut -d' ' -f1)" \
    == "$expected_script_sha256" ]] || fail 'cópia root-owned do script diverge'
/bin/bash -n "${work_directory}/build-dre-images.sh"
/bin/bash "${work_directory}/build-dre-images.sh" \
  "$remote_root" "$source_revision" "$source_archive_sha256" \
  "$buildkit_archive_sha256"
'@
    $script = $template.Replace('__REMOTE_ROOT__', $RemoteRoot)
    $script = $script.Replace('__SOURCE_REVISION__', $SourceRevision)
    $script = $script.Replace('__SOURCE_ARCHIVE_SHA256__', $SourceArchiveSha256)
    $script = $script.Replace('__BUILDKIT_ARCHIVE_SHA256__', $BuildKitArchiveSha256)
    $script = $script.Replace('__BUILD_SCRIPT_SHA256__', $BuildScriptSha256)
    return $script.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Invoke-DreImageBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SshArguments,

        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$RemoteRoot,

        [Parameter(Mandatory = $true)]
        [string]$SourceRevision,

        [Parameter(Mandatory = $true)]
        [string]$SourceArchiveSha256,

        [Parameter(Mandatory = $true)]
        [string]$BuildKitArchiveSha256,

        [Parameter(Mandatory = $true)]
        [string]$BuildScriptSha256
    )

    if ($Server -cne 'apiadmin@192.168.100.59') {
        throw 'O build DRE aceita somente o servidor físico aprovado.'
    }
    if ($SourceRevision -cnotmatch '^[0-9a-f]{40}$' -or
        $SourceArchiveSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $BuildKitArchiveSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $BuildScriptSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Revisão ou SHA-256 inválido para o build DRE.'
    }
    $revisionPrefix = $SourceRevision.Substring(0, 12)
    $expectedRootPattern =
        '^/home/apiadmin/dre-image-build-' +
        [Regex]::Escape($revisionPrefix) + '-[0-9]{8}T[0-9]{6}Z$'
    if ($RemoteRoot -cnotmatch $expectedRootPattern) {
        throw 'Diretório remoto fora do staging fechado do build DRE.'
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

    $wrapperArguments = @{
        RemoteRoot = $RemoteRoot
        SourceRevision = $SourceRevision
        SourceArchiveSha256 = $SourceArchiveSha256
        BuildKitArchiveSha256 = $BuildKitArchiveSha256
        BuildScriptSha256 = $BuildScriptSha256
    }
    $rootScript = New-DreImageBuildRootWrapper @wrapperArguments
    $encodedScript = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes($rootScript)
    )
    $remoteCommand =
        "sudo -S -p '' -- /bin/bash -c `"printf '%s' '$encodedScript' | " +
        "base64 --decode | /bin/bash`""

    $envFile = 'C:\github\servidor\.env'
    $password = Read-DreImageBuildSudoPassword -EnvFile $envFile
    try {
        $password | & ssh.exe @SshArguments $Server $remoteCommand
        if ($LASTEXITCODE -ne 0) {
            throw 'Build remoto autenticado das imagens DRE falhou.'
        }
    }
    finally {
        $password = $null
        $rootScript = $null
        $encodedScript = $null
        $remoteCommand = $null
    }
}

Export-ModuleMember -Function Invoke-DreImageBuild
