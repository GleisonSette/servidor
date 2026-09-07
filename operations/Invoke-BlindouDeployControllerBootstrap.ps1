[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ServerCommit,

    [Parameter(Mandatory = $true)]
    [ValidateSet('INSTALAR BLINDOU DEPLOYCTL')]
    [string]$Confirmation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$remoteRoot = "/home/apiadmin/blindou-platform-bootstrap-deployctl/$ServerCommit"
$remoteArchive = "/home/apiadmin/blindou-platform-bootstrap-deployctl-$ServerCommit.tar.gz"
$archivePaths = @(
    'operations/remote/blindou-deployctl',
    'operations/remote/blindou-release-emergencyctl',
    'operations/remote/blindou-release-verify.py',
    'operations/remote/blindou-ghcr-pull-verify.py',
    'operations/remote/blindou-pagarme-plans.py',
    'operations/remote/blindou-dispatch-v3-jetstream.py',
    'operations/remote/blindou-dispatch-v3-truststore.py',
    'operations/remote/blindou-platform-metrics',
    'operations/remote/blindou-platform-metrics.service',
    'operations/remote/blindou-platform-metrics.timer',
    'operations/remote/blindou-deployctl.sudoers',
    'operations/remote/blindou-release-allowed-signers',
    'operations/remote/blindou-backup-recipient.crt',
    'operations/remote/bootstrap-blindou-deployctl.sh',
    'platform/blindou',
    'platform/base/service-exposure-policy.yaml'
)

function Invoke-CheckedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage Código de saída: $LASTEXITCODE."
    }
}

foreach ($required in @($identity, $knownHosts)) {
    $item = Get-Item -LiteralPath $required -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'A identidade SSH ou known_hosts possui tipo inseguro.'
    }
}

$sshArgs = @(
    '-F', 'NUL',
    '-i', $identity,
    '-o', 'IdentitiesOnly=yes',
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=15',
    '-o', 'KexAlgorithms=curve25519-sha256',
    '-o', 'HostKeyAlgorithms=ssh-ed25519',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$knownHosts"
)

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) `
    ('blindou-deployctl-bootstrap-' + [guid]::NewGuid().ToString('N'))
$archive = Join-Path $temporaryRoot 'controller.tar.gz'

Push-Location $repositoryRoot
try {
    $head = (& git.exe rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $head -cne $ServerCommit) {
        throw 'ServerCommit não corresponde ao HEAD local.'
    }
    if ((& git.exe status --porcelain=v1 --untracked-files=all)) {
        throw 'O worktree do controlador precisa estar integralmente limpo.'
    }
    [void](New-Item -ItemType Directory -Path $temporaryRoot)
    Invoke-CheckedProcess -FilePath 'git.exe' `
        -ArgumentList (@('archive', '--format=tar.gz', "--output=$archive", $ServerCommit, '--') + $archivePaths) `
        -FailureMessage 'Não foi possível criar o archive seletivo do controlador.'
    $archiveSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
    $controllerSha256 = (git.exe show "${ServerCommit}:operations/remote/blindou-deployctl" |
        ForEach-Object { $_ }) -join "`n"
    $emergencySha256 = (git.exe show "${ServerCommit}:operations/remote/blindou-release-emergencyctl" |
        ForEach-Object { $_ }) -join "`n"
    $controllerSha256 = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($controllerSha256 + "`n"))
    ).ToLowerInvariant()
    $emergencySha256 = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($emergencySha256 + "`n"))
    ).ToLowerInvariant()

    Invoke-CheckedProcess -FilePath 'scp.exe' `
        -ArgumentList ($sshArgs + @($archive, "${server}:$remoteArchive.uploading")) `
        -FailureMessage 'Não foi possível transportar o controlador.'
    $prepare = @"
set -eu
test "`$(hostname)" = apiwpp
test "`$(sha256sum '$remoteArchive.uploading' | cut -d' ' -f1)" = '$archiveSha256'
mv -f -- '$remoteArchive.uploading' '$remoteArchive'
install -d -m 0700 '$remoteRoot'
tar --extract --gzip --file '$remoteArchive' --directory '$remoteRoot'
chmod 0755 '$remoteRoot/operations/remote/bootstrap-blindou-deployctl.sh'
"@
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArgs + @($server, $prepare)) `
        -FailureMessage 'O staging remoto do controlador divergiu.'

    Import-Module (Join-Path $PSScriptRoot 'Blindou.SudoBootstrap.psm1') -Force
    $bootstrapBusy = $false
    try {
        Invoke-BlindouSudoBootstrap `
            -ControllerSet DeployController `
            -SshArguments $sshArgs `
            -Server $server `
            -RemoteRoot $remoteRoot
    }
    catch {
        if ($_.Exception.Message -cne 'Bootstrap remoto autenticado falhou.') {
            throw
        }
        $bootstrapBusy = $true
    }

    $postInstall = @"
set -eu
test "`$(hostname)" = apiwpp
test "`$(stat -c '%U:%G:%a' /usr/local/sbin/blindou-deployctl)" = root:root:755
test "`$(stat -c '%U:%G:%a' /usr/local/sbin/blindou-release-emergencyctl)" = root:root:755
test "`$(sha256sum /usr/local/sbin/blindou-deployctl | cut -d' ' -f1)" = '$controllerSha256'
test "`$(sha256sum /usr/local/sbin/blindou-release-emergencyctl | cut -d' ' -f1)" = '$emergencySha256'
if [ '$bootstrapBusy' = True ]; then
  set +e
  sudo -n /usr/local/sbin/blindou-deployctl status >/dev/null 2>&1
  result=`$?
  set -e
  test "`$result" = 2
else
  sudo -n /usr/local/sbin/blindou-deployctl status >/dev/null
fi
printf 'blindou_deployctl_files=passed bootstrap_busy=%s\n' '$bootstrapBusy'
"@
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArgs + @($server, $postInstall)) `
        -FailureMessage 'A verificação posterior dos arquivos instalados falhou.'
    Write-Output "blindou_deployctl_bootstrap=passed commit=$ServerCommit archive_sha256=$archiveSha256 busy=$bootstrapBusy"
}
finally {
    Pop-Location
    if (Test-Path -LiteralPath $temporaryRoot) {
        $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
        $resolvedSystemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Diretório temporário resolveu fora da raiz esperada.'
        }
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}
