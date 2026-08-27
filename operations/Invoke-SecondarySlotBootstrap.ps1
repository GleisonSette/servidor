[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SecondarySlot.SudoBootstrap.psm1') -Force

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$server = 'apiadmin@192.168.100.59'
$archivePaths = @(
    'operations/Invoke-SecondarySlotBootstrap.ps1',
    'operations/SecondarySlot.SudoBootstrap.psm1',
    'operations/remote/bootstrap-secondary-slotctl.sh',
    'operations/remote/secondary-slotctl',
    'operations/remote/secondary-slotctl.sudoers',
    'operations/remote/secondary-slot-metrics.service',
    'operations/remote/secondary-slot-metrics.timer',
    'operations/remote/secondary-slot-tmpfiles.conf',
    'operations/remote/secondary_slot.py',
    'operations/remote/test-secondary-slot.py',
    'operations/remote/verify-secondary-slot-artifacts.py',
    'platform/base/namespaces.yaml',
    'platform/saferwpp/00-platform-namespaces.yaml',
    'platform/secondary-slot',
    'runbooks/secondary-slot.md'
)

function Invoke-CheckedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage Código de saída: $LASTEXITCODE."
    }
}

Push-Location $repositoryRoot
try {
    Invoke-CheckedProcess -FilePath 'git.exe' `
        -ArgumentList (@('diff', '--quiet', '--') + $archivePaths) `
        -FailureMessage 'Os artefatos do slot possuem alterações não commitadas.'
    Invoke-CheckedProcess -FilePath 'python.exe' `
        -ArgumentList @('operations/remote/verify-secondary-slot-artifacts.py') `
        -FailureMessage 'A verificação offline do slot falhou.'

    $gitCommit = (& git.exe rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $gitCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Não foi possível determinar o commit aprovado.'
    }
    $shortCommit = $gitCommit.Substring(0, 12)
    $localReleaseDirectory = Join-Path $env:LOCALAPPDATA `
        "SaferDock\saferwpp\platform\$gitCommit\secondary-slot"
    New-Item -ItemType Directory -Path $localReleaseDirectory -Force | Out-Null
    $archive = Join-Path $localReleaseDirectory `
        "servidor-secondary-slot-$shortCommit.tar.gz"
    $temporaryArchive = "$archive.tmp"
    if (Test-Path -LiteralPath $temporaryArchive) {
        Remove-Item -LiteralPath $temporaryArchive -Force
    }
    Invoke-CheckedProcess -FilePath 'git.exe' `
        -ArgumentList (@(
            'archive',
            '--format=tar.gz',
            "--output=$temporaryArchive",
            $gitCommit,
            '--'
        ) + $archivePaths) `
        -FailureMessage 'Não foi possível criar o arquivo seletivo do slot.'
    Move-Item -LiteralPath $temporaryArchive -Destination $archive -Force
    $expectedSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).
        Hash.ToLowerInvariant()

    $sshDirectory = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh'
    $identityFile = Join-Path $sshDirectory 'apiwpp_admin_ed25519'
    $knownHostsFile = Join-Path $sshDirectory 'known_hosts'
    foreach ($requiredFile in @($identityFile, $knownHostsFile)) {
        $item = Get-Item -LiteralPath $requiredFile -Force -ErrorAction Stop
        if ($item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'A identidade SSH ou known_hosts possui tipo inseguro.'
        }
    }
    $sshArguments = @(
        '-F', 'NUL',
        '-i', $identityFile,
        '-o', 'IdentitiesOnly=yes',
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=15',
        '-o', 'KexAlgorithms=curve25519-sha256',
        '-o', 'HostKeyAlgorithms=ssh-ed25519',
        '-o', 'StrictHostKeyChecking=yes',
        '-o', "UserKnownHostsFile=$knownHostsFile"
    )
    $remoteDirectory = "/home/apiadmin/saferwpp-secondary-slot-bootstrap-$shortCommit"
    $remoteArchive = "$remoteDirectory/servidor-secondary-slot-$shortCommit.tar.gz"
    $remoteTemporaryArchive = "$remoteArchive.uploading"
    $remotePreflight = @'
set -eu
test "$(hostname)" = apiwpp
sudo -n /usr/local/sbin/apiwpp-deployctl verify
sudo -n /usr/local/sbin/blindou-deployctl status >/dev/null
'@
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @($server, $remotePreflight)) `
        -FailureMessage 'O preflight do host, APIWPP ou Blindou falhou.'
    $prepareStaging =
        "install -d -m 0700 '$remoteDirectory' && " +
        "rm -f -- '$remoteTemporaryArchive'"
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @($server, $prepareStaging)) `
        -FailureMessage 'Não foi possível preparar o staging remoto.'

    $scpArguments = $sshArguments + @($archive, "${server}:$remoteTemporaryArchive")
    Invoke-CheckedProcess -FilePath 'scp.exe' `
        -ArgumentList $scpArguments `
        -FailureMessage 'Não foi possível transportar o arquivo do slot.'
    $finalizeStaging =
        "chmod 0600 '$remoteTemporaryArchive' && " +
        "mv -f -- '$remoteTemporaryArchive' '$remoteArchive' && " +
        "test `$(sha256sum '$remoteArchive' | cut -d' ' -f1) = '$expectedSha256'"
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @($server, $finalizeStaging)) `
        -FailureMessage 'O SHA-256 remoto do arquivo do slot diverge.'

    Invoke-SecondarySlotSudoBootstrap `
        -SshArguments $sshArguments `
        -Server $server `
        -RemoteArchive $remoteArchive `
        -ExpectedSha256 $expectedSha256 `
        -GitCommit $gitCommit

    $postInstall = @'
sudo -n /usr/local/sbin/secondary-slotctl status
sudo -n /usr/local/sbin/apiwpp-deployctl verify
sudo -n /usr/local/sbin/blindou-deployctl status >/dev/null
printf 'blindou_deployctl_status=passed\n'
sudo -n /usr/local/sbin/blindou-hostctl verify
'@
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @($server, $postInstall)) `
        -FailureMessage 'A verificação posterior à instalação falhou.'

    Write-Output (
        'secondary_slot_bootstrap=passed ' +
        "commit=$gitCommit sha256=$expectedSha256 remote=$remoteArchive"
    )
}
finally {
    Pop-Location
}
