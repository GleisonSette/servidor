[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ServerCommit,

    [Parameter(Mandatory = $true)]
    [ValidateSet('INSTALAR BLINDOU DATACTL')]
    [string]$Confirmation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$remoteRoot = "/home/apiadmin/blindou-data-bootstrap/$ServerCommit"
$remoteArchive = "/home/apiadmin/blindou-data-bootstrap-$ServerCommit.tar.gz"
$archivePaths = @(
    'operations/remote/blindou-datactl',
    'operations/remote/blindou-datactl.sudoers',
    'operations/remote/blindou-data-release-verify.py',
    'operations/remote/blindou-data-secret-verify.py',
    'operations/remote/blindou-data-ghcr-pull-verify.py',
    'operations/remote/bootstrap-blindou-datactl.sh',
    'operations/remote/verify-blindou-data-artifacts.py',
    'platform/blindou/20-production-workload-policy.yaml',
    'platform/blindou-data'
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
    ('blindou-data-bootstrap-' + [guid]::NewGuid().ToString('N'))
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
chmod 0755 '$remoteRoot/operations/remote/bootstrap-blindou-datactl.sh'
"@
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArgs + @($server, $prepare)) `
        -FailureMessage 'O staging remoto do controlador divergiu.'

    Import-Module (Join-Path $PSScriptRoot 'Blindou.SudoBootstrap.psm1') -Force
    Invoke-BlindouSudoBootstrap `
        -ControllerSet DataController `
        -SshArguments $sshArgs `
        -Server $server `
        -RemoteRoot $remoteRoot

    $postInstall = @'
set -eu
sudo -n /usr/local/sbin/blindou-datactl status
sudo -n /usr/local/sbin/blindou-datactl verify-quarantine
sudo -n /usr/local/sbin/blindou-hostctl verify
sudo -n /usr/local/sbin/apiwpp-deployctl verify
sudo -n /usr/local/sbin/blindou-deployctl status >/dev/null
printf 'blindou_deployctl_status=passed\n'
'@
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArgs + @($server, $postInstall)) `
        -FailureMessage 'A verificação posterior ao bootstrap falhou.'
    Write-Output "blindou_data_controller_bootstrap=passed commit=$ServerCommit archive_sha256=$archiveSha256"
}
finally {
    Pop-Location
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
