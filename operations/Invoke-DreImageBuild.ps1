[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Dre.ImageBuild.psm1') -Force

$server = 'apiadmin@192.168.100.59'
$sourceRevision = '25dc4f8996699a5c9870294666391eb8bbab7c3e'
$remoteRoot =
    '/home/apiadmin/dre-image-build-25dc4f899669-20260830T221500Z'
$sourceArchiveSha256 =
    'a5303a241928ea78223bf7cddfb5425fc77d14acbc96c9c249dcca586ad70099'
$buildKitArchiveSha256 =
    '2975d0f651ad96ba8b80b9992ae1f9a964f4408569af5b6dc36544165c3926af'
$buildScriptSha256 =
    '627c7655b922333dfe32a34002bbe1e5e15f4643871235084e599ec8f416bf8c'
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
