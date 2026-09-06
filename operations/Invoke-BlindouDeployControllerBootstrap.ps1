[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Blindou.SudoBootstrap.psm1') -Force

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$server = 'apiadmin@192.168.100.59'
$archivePaths = @(
    'operations/remote/blindou-deployctl',
    'operations/remote/blindou-deployctl.sudoers',
    'operations/remote/blindou-release-emergencyctl',
    'operations/remote/blindou-release-verify.py',
    'operations/remote/blindou-ghcr-pull-verify.py',
    'operations/remote/blindou-pagarme-plans.py',
    'operations/remote/blindou-platform-metrics',
    'operations/remote/blindou-platform-metrics.service',
    'operations/remote/blindou-platform-metrics.timer',
    'operations/remote/blindou-release-allowed-signers',
    'operations/remote/blindou-backup-recipient.crt',
    'operations/remote/bootstrap-blindou-deployctl.sh',
    'platform/blindou/00-namespaces.yaml',
    'platform/blindou/10-quarantine.yaml',
    'platform/blindou/15-edge-connector-gate.yaml',
    'platform/blindou/16-edge-connector-runtime.yaml',
    'platform/blindou/20-production-workload-policy.yaml',
    'platform/base/service-exposure-policy.yaml'
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

function Wait-BlindouRemoteInterval {
    Start-Sleep -Seconds 15
}

Push-Location $repositoryRoot
try {
    Invoke-CheckedProcess -FilePath 'git.exe' `
        -ArgumentList (@('diff', '--quiet', '--') + $archivePaths) `
        -FailureMessage 'Os artefatos do controlador Blindou possuem alterações não commitadas.'

    Invoke-CheckedProcess -FilePath 'powershell.exe' `
        -ArgumentList @(
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            'scripts\Test-Repository.ps1'
        ) `
        -FailureMessage 'A verificação offline do repositório falhou.'

    $gitCommit = (& git.exe rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $gitCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Não foi possível determinar o commit aprovado.'
    }
    $shortCommit = $gitCommit.Substring(0, 12)
    $localReleaseDirectory = Join-Path $env:LOCALAPPDATA `
        "SaferDock\blindou\controller-bootstrap\$gitCommit"
    New-Item -ItemType Directory -Path $localReleaseDirectory -Force | Out-Null
    $archive = Join-Path $localReleaseDirectory `
        "blindou-deploy-controller-$shortCommit.tar.gz"
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
        -FailureMessage 'Não foi possível criar o arquivo seletivo do controlador Blindou.'
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
        '-o', 'PreferredAuthentications=publickey',
        '-o', 'PasswordAuthentication=no',
        '-o', 'KbdInteractiveAuthentication=no',
        '-o', 'KexAlgorithms=curve25519-sha256',
        '-o', 'HostKeyAlgorithms=ssh-ed25519',
        '-o', 'StrictHostKeyChecking=yes',
        '-o', "UserKnownHostsFile=$knownHostsFile"
    )
    $operationSuffix = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
    $remoteRoot = "/home/apiadmin/blindou-platform-bootstrap-dre-$operationSuffix/$gitCommit"
    $remoteArchive = "$remoteRoot/blindou-deploy-controller-$shortCommit.tar.gz"

    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @(
            $server,
            "install -d -m 0700 '$remoteRoot'"
        )) `
        -FailureMessage 'Não foi possível preparar o staging remoto Blindou.'
    Wait-BlindouRemoteInterval

    Invoke-CheckedProcess -FilePath 'scp.exe' `
        -ArgumentList ($sshArguments + @($archive, "${server}:$remoteArchive")) `
        -FailureMessage 'Não foi possível transportar o controlador Blindou.'
    Wait-BlindouRemoteInterval

    $extract =
        "cd '$remoteRoot' && " +
        "test `$(sha256sum '$remoteArchive' | cut -d' ' -f1) = '$expectedSha256' && " +
        "tar -xzf '$remoteArchive' && " +
        "chmod 0755 operations/remote/bootstrap-blindou-deployctl.sh " +
        "operations/remote/blindou-deployctl " +
        "operations/remote/blindou-release-emergencyctl " +
        "operations/remote/blindou-platform-metrics"
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @($server, $extract)) `
        -FailureMessage 'Não foi possível extrair o controlador Blindou.'
    Wait-BlindouRemoteInterval

    Invoke-BlindouSudoBootstrap `
        -ControllerSet DeployController `
        -SshArguments $sshArguments `
        -Server $server `
        -RemoteRoot $remoteRoot
    Wait-BlindouRemoteInterval

    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @(
            $server,
            'sudo -n /usr/local/sbin/blindou-deployctl status'
        )) `
        -FailureMessage 'O status final do controlador Blindou falhou.'

    Write-Output (
        'blindou_deploy_controller_bootstrap=passed ' +
        "commit=$gitCommit sha256=$expectedSha256 remote=$remoteArchive"
    )
}
finally {
    Pop-Location
}
