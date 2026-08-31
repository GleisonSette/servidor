[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Dre.SudoBootstrap.psm1') -Force

$server = 'apiadmin@192.168.100.59'
$remoteRoot =
    '/home/apiadmin/dre-controller-bootstrap-4902604dad96-20260831T012811Z'
$archiveSha256 =
    '5030374e9e96be8b608c6918731fa97716a8b1706c8ea92fc5cb9c611dd3bff7'
$publicKeySha256 =
    '4902604dad96d9b07f4010308d30e3815cb4e76446855d925079be0e3b922ce9'
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

Invoke-DreSudoBootstrap `
    -SshArguments $sshArguments `
    -Server $server `
    -RemoteRoot $remoteRoot `
    -ExpectedArchiveSha256 $archiveSha256 `
    -PublicKeySha256 $publicKeySha256

Write-Output (
    'dre_sudo_bootstrap=passed ' +
    "archive_sha256=$archiveSha256 public_key_sha256=$publicKeySha256"
)
