[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$server = 'apiadmin@192.168.100.59'
$sourceRevision = '25dc4f8996699a5c9870294666391eb8bbab7c3e'
$remoteRoot =
    '/home/apiadmin/dre-image-build-25dc4f899669-20260830T221500Z'
$publishScriptSha256 =
    '92776fcbf215e5bdd32e86f80530714983f84f4d96be91fc5bde51c391523d7a'
$regctlSha256 =
    'c93aa7638749f5aaac1a8e01787321889c78f0101809bb2880343478d0ba0467'
$syftSha256 =
    '2a2e837a2c8d59ec9af5472ee22d3b04ee463c4e44476ecf993fd1e5ab6ebc7f'
$trivySha256 =
    'bbb64b9695866ce4a7a8f5c9592002c5961cab378577fa3f8a040df362b9b2ea'
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

$gh = Get-Command gh -CommandType Application -ErrorAction Stop
$login = (& $gh.Source api user --jq .login).Trim()
if ($LASTEXITCODE -ne 0 -or $login -cne 'GleisonSette') {
    throw 'A sessão GitHub ativa não pertence à conta GleisonSette.'
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

$publishScript = "$remoteRoot/publish-dre-images.sh"
$remoteCommand =
    "printf '%s  %s\n' '$publishScriptSha256' '$publishScript' | " +
    "sha256sum -c - >/dev/null && /bin/bash '$publishScript' " +
    "'$remoteRoot' '$sourceRevision' '$regctlSha256' '$syftSha256' '$trivySha256'"

$token = $null
try {
    $tokenLines = @(& $gh.Source auth token)
    if ($LASTEXITCODE -ne 0 -or $tokenLines.Count -ne 1) {
        throw 'Não foi possível obter uma credencial GitHub única do keyring.'
    }
    $token = [string]$tokenLines[0]
    if ([string]::IsNullOrEmpty($token) -or $token.Length -gt 1024 -or
        $token.IndexOf([char]0) -ge 0 -or
        $token.Contains("`r") -or $token.Contains("`n")) {
        throw 'A credencial GitHub possui formato inválido.'
    }
    $token | & ssh.exe @sshArguments $server $remoteCommand
    if ($LASTEXITCODE -ne 0) {
        throw 'Scan ou publicação das imagens DRE falhou.'
    }
}
finally {
    $token = $null
    $tokenLines = $null
    $remoteCommand = $null
}

Write-Output (
    'dre_image_publish_orchestrator=passed ' +
    "source_revision=$sourceRevision publish_script_sha256=$publishScriptSha256"
)
