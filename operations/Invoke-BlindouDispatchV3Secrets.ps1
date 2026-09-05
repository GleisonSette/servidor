[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$sshArgs = @(
    '-F', 'NUL',
    '-i', $identity,
    '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$knownHosts"
)

function ConvertFrom-ProtectedValue {
    param([Parameter(Mandatory = $true)][Security.SecureString]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function ConvertTo-Base64Utf8 {
    param([Parameter(Mandatory = $true)][string]$Value)

    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function Invoke-ClosedSshInput {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteCommand,
        [Parameter(Mandatory = $true)][string]$Payload
    )

    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $argumentList = @(
            '-F NUL',
            "-i `"$identity`"",
            '-o IdentitiesOnly=yes',
            '-o StrictHostKeyChecking=yes',
            "-o UserKnownHostsFile=`"$knownHosts`"",
            $server,
            $RemoteCommand
        ) -join ' '
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'ssh.exe'
        $startInfo.Arguments = $argumentList
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw 'Não foi possível iniciar o SSH seguro.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.NewLine = "`n"
        $process.StandardInput.Write($Payload)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($stdout) { Write-Host $stdout.TrimEnd() }
        if ($process.ExitCode -eq 0) { return }
        if ($process.ExitCode -ne 2) {
            if ($stderr) { Write-Host $stderr.TrimEnd() -ForegroundColor Red }
            throw 'Provisionamento fechado do material Dispatch V3 falhou.'
        }
        if ($attempt -eq 12) {
            throw 'O controlador permaneceu ocupado por um minuto.'
        }
        Write-Host 'O coletor de métricas está usando o controlador; nova tentativa em 5 segundos.' `
            -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

foreach ($required in @($identity, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Arquivo administrativo ausente: $required"
    }
}

$endpointSecure = $null
$accessKeySecure = $null
$secretKeySecure = $null
$endpoint = $null
$accessKey = $null
$secretKey = $null
$payload = $null
try {
    $Host.UI.RawUI.WindowTitle = 'Blindou - material protegido do Dispatch V3'
    $status = (& ssh.exe @sshArgs $server `
        'sudo -n /usr/local/sbin/blindou-deployctl status' 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $status -notmatch '(?m)^dispatch_v3_state=') {
        throw 'O controlador Dispatch V3 versionado não está disponível no host.'
    }

    Write-Host 'Informe somente o endpoint HTTPS base da UAZAPI, sem token ou credencial.' `
        -ForegroundColor Cyan
    $endpointSecure = Read-Host 'Endpoint HTTPS da UAZAPI' -AsSecureString
    Write-Host 'Informe a credencial Cloudflare R2 restrita a leitura de objetos no bucket Blindou.' `
        -ForegroundColor Cyan
    $accessKeySecure = Read-Host 'ID da chave R2 somente leitura' -AsSecureString
    $secretKeySecure = Read-Host 'Chave secreta R2 somente leitura' -AsSecureString

    $endpoint = (ConvertFrom-ProtectedValue $endpointSecure).Trim()
    $accessKey = (ConvertFrom-ProtectedValue $accessKeySecure).Trim()
    $secretKey = (ConvertFrom-ProtectedValue $secretKeySecure).Trim()
    $endpointUri = $null
    if (-not [Uri]::TryCreate($endpoint, [UriKind]::Absolute, [ref]$endpointUri) -or
        $endpointUri.Scheme -cne 'https' -or
        [string]::IsNullOrWhiteSpace($endpointUri.Host) -or
        -not [string]::IsNullOrEmpty($endpointUri.UserInfo) -or
        -not [string]::IsNullOrEmpty($endpointUri.Query) -or
        -not [string]::IsNullOrEmpty($endpointUri.Fragment)) {
        throw 'O endpoint precisa ser HTTPS absoluto e não pode conter credencial, query ou fragmento.'
    }
    if ($accessKey -notmatch '^[A-Za-z0-9]{20,128}$') {
        throw 'O ID da chave R2 não possui o formato esperado.'
    }
    if ($secretKey -notmatch '^[A-Za-z0-9]{32,256}$') {
        throw 'A chave secreta R2 não possui o formato esperado.'
    }

    $payload = @(
        'schema=1',
        (ConvertTo-Base64Utf8 $endpoint),
        (ConvertTo-Base64Utf8 $accessKey),
        (ConvertTo-Base64Utf8 $secretKey)
    ) -join "`n"
    $payload += "`n"
    Invoke-ClosedSshInput `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl provision-dispatch-v3-secrets blindou-dispatch-v3-secrets' `
        -Payload $payload

    $endpoint = $null
    $accessKey = $null
    $secretKey = $null
    $payload = $null
    & ssh.exe @sshArgs $server `
        'sudo -n /usr/local/sbin/blindou-deployctl verify-dispatch-v3'
    if ($LASTEXITCODE -ne 0) {
        throw 'A verificação posterior do material Dispatch V3 falhou.'
    }
    Write-Host 'Material Dispatch V3 validado e preparado; novas admissões continuam inativas.' `
        -ForegroundColor Green
}
finally {
    $endpoint = $null
    $accessKey = $null
    $secretKey = $null
    $payload = $null
    if ($null -ne $endpointSecure) { $endpointSecure.Dispose() }
    if ($null -ne $accessKeySecure) { $accessKeySecure.Dispose() }
    if ($null -ne $secretKeySecure) { $secretKeySecure.Dispose() }
}

