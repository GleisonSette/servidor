[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$server = 'apiadmin@192.168.100.59'
$sourceRevision = 'd2abe4507b74f4303305a58c250557c92ee1df56'
$remoteRoot =
    '/home/apiadmin/dre-image-build-d2abe4507b74-20260902T133025Z'
$publishScriptSha256 =
    'eb56421e194ddad8d8239907064aabd8b3132230bfb372ff92ee10e983908c63'
$regctlSha256 =
    'c93aa7638749f5aaac1a8e01787321889c78f0101809bb2880343478d0ba0467'
$syftSha256 =
    '5a8b71e94f4607973145f02e27e01d50b9f7c7bc41e38d40b39606ad138b43b5'
$trivySha256 =
    '0e69edd134a3c338baa1a6806920773615d682b18cbc6a0cba2a3b658ef9b63e'
$sshDirectory = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh'
$identityFile = Join-Path $sshDirectory 'apiwpp_admin_ed25519'
$knownHostsFile = Join-Path $sshDirectory 'known_hosts'

function ConvertTo-WindowsProcessArgument {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($Value.Length -eq 0) {
        return '""'
    }
    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    # ProcessStartInfo.Arguments follows the Windows command-line escaping
    # rules. Backslashes immediately before a quote (including the closing
    # quote) must be doubled so ssh.exe receives each value as one argument.
    $quoted = [Text.StringBuilder]::new()
    [void]$quoted.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            if ($backslashes -gt 0) {
                [void]$quoted.Append(('\' * ($backslashes * 2)))
                $backslashes = 0
            }
            [void]$quoted.Append('\')
            [void]$quoted.Append('"')
            continue
        }
        if ($backslashes -gt 0) {
            [void]$quoted.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$quoted.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$quoted.Append(('\' * ($backslashes * 2)))
    }
    [void]$quoted.Append('"')
    return $quoted.ToString()
}

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
$tokenLines = $null
$startInfo = $null
$sshProcess = $null
$sshStarted = $false
try {
    $tokenLines = @(& $gh.Source auth token)
    if ($LASTEXITCODE -ne 0 -or $tokenLines.Count -ne 1) {
        throw 'Não foi possível obter uma credencial GitHub única do keyring.'
    }
    $token = [string]$tokenLines[0]
    $tokenLines = $null
    if ([string]::IsNullOrEmpty($token) -or $token.Length -gt 1024 -or
        $token.IndexOf([char]0) -ge 0 -or
        $token.Contains("`r") -or $token.Contains("`n")) {
        throw 'A credencial GitHub possui formato inválido.'
    }
    $ssh = Get-Command ssh.exe -CommandType Application -ErrorAction Stop
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ssh.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.Arguments = (@($sshArguments) + @($server, $remoteCommand) |
        ForEach-Object { ConvertTo-WindowsProcessArgument -Value $_ }) -join ' '
    $sshProcess = [Diagnostics.Process]::new()
    $sshProcess.StartInfo = $startInfo
    if (-not $sshProcess.Start()) {
        throw 'Não foi possível iniciar o transporte SSH da publicação DRE.'
    }
    $sshStarted = $true
    $sshProcess.StandardInput.NewLine = "`n"
    $sshProcess.StandardInput.WriteLine($token)
    $sshProcess.StandardInput.Close()
    $token = $null
    $sshProcess.WaitForExit()
    if ($sshProcess.ExitCode -ne 0) {
        throw 'Scan ou publicação das imagens DRE falhou.'
    }
}
finally {
    $token = $null
    $tokenLines = $null
    $remoteCommand = $null
    $startInfo = $null
    if ($null -ne $sshProcess) {
        if ($sshStarted -and -not $sshProcess.HasExited) {
            $sshProcess.Kill($true)
            $sshProcess.WaitForExit()
        }
        $sshProcess.Dispose()
        $sshProcess = $null
    }
    $sshStarted = $false
}

Write-Output (
    'dre_image_publish_orchestrator=passed ' +
    "source_revision=$sourceRevision publish_script_sha256=$publishScriptSha256"
)
