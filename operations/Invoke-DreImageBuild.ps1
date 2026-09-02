[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Dre.ImageBuild.psm1') -Force

$server = 'apiadmin@192.168.100.59'
$sourceRevision = '69716bb0a23e02cc839f1adac0a41fbc521f7f04'
$remoteRoot =
    '/home/apiadmin/dre-image-build-69716bb0a23e-20260902T050116Z'
$sourceArchiveSha256 =
    '17ab942c6527f086e4c36298488840c05a981c8db9f2c60ec8305db787635640'
$buildKitArchiveSha256 =
    '2975d0f651ad96ba8b80b9992ae1f9a964f4408569af5b6dc36544165c3926af'
$buildScriptSha256 =
    'ecf9961e3ec3a06b9b4521c234d8c838e02d9c1c8e41177a604fb1904656a30f'
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
    '-o', 'ServerAliveInterval=15',
    '-o', 'ServerAliveCountMax=12',
    '-o', 'PreferredAuthentications=publickey',
    '-o', 'PasswordAuthentication=no',
    '-o', 'KbdInteractiveAuthentication=no',
    '-o', 'KexAlgorithms=curve25519-sha256',
    '-o', 'HostKeyAlgorithms=ssh-ed25519',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$knownHostsFile"
)

$buildArguments = @{
    SshArguments = $sshArguments
    Server = $server
    RemoteRoot = $remoteRoot
    SourceRevision = $sourceRevision
    SourceArchiveSha256 = $sourceArchiveSha256
    BuildKitArchiveSha256 = $buildKitArchiveSha256
    BuildScriptSha256 = $buildScriptSha256
}
Invoke-DreImageBuild @buildArguments

Write-Output (
    'dre_image_build_orchestrator=passed ' +
    "source_revision=$sourceRevision source_archive_sha256=$sourceArchiveSha256 " +
    "buildkit_archive_sha256=$buildKitArchiveSha256 " +
    "build_script_sha256=$buildScriptSha256"
)
