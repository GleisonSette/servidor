[CmdletBinding()]
param(
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$utf8Encoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding
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

function Test-ProviderInputs {
    param(
        [Parameter(Mandatory = $true)][string]$UazapiEndpoint,
        [Parameter(Mandatory = $true)][string]$UazapiAdminToken,
        [Parameter(Mandatory = $true)][string]$ResendApiKey,
        [Parameter(Mandatory = $true)][string]$EmailFrom
    )

    $endpointUri = $null
    if (-not [Uri]::TryCreate($UazapiEndpoint, [UriKind]::Absolute, [ref]$endpointUri) -or
        $endpointUri.Scheme -cne 'https' -or
        [string]::IsNullOrWhiteSpace($endpointUri.Host) -or
        -not [string]::IsNullOrEmpty($endpointUri.UserInfo) -or
        -not [string]::IsNullOrEmpty($endpointUri.Query) -or
        -not [string]::IsNullOrEmpty($endpointUri.Fragment)) {
        throw 'O endpoint precisa ser HTTPS absoluto e não pode conter credencial, query ou fragmento.'
    }
    if ($UazapiAdminToken -notmatch '^[^\s\p{Cc}]{16,2048}$') {
        throw 'O token administrativo da UAZAPI não possui o formato esperado.'
    }
    if ($ResendApiKey -notmatch '^re_[A-Za-z0-9_-]{16,512}$') {
        throw 'A chave da Resend não possui o formato esperado.'
    }
    if ($EmailFrom -notmatch '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$' -or
        $EmailFrom.EndsWith('.invalid', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'O e-mail remetente não possui o formato esperado.'
    }
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
        $startInfo.StandardOutputEncoding = $utf8Encoding
        $startInfo.StandardErrorEncoding = $utf8Encoding
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
            throw 'Preparação protegida das credenciais UAZAPI/Resend falhou.'
        }
        if ($attempt -eq 12) {
            throw 'O controlador permaneceu ocupado por um minuto.'
        }
        Write-Host 'O coletor de métricas está usando o controlador; nova tentativa em 5 segundos.' `
            -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

if ($SelfTest) {
    Test-ProviderInputs `
        -UazapiEndpoint 'https://blindou.uazapi.com' `
        -UazapiAdminToken 'synthetic-uazapi-token-123456' `
        -ResendApiKey 're_synthetic_resend_key_123456' `
        -EmailFrom 'notificacoes@blindou.com'
    $expectedPortuguese = -join ([char[]](112, 114, 111, 100, 117, 231, 227, 111))
    if ('produção' -cne $expectedPortuguese) {
        throw 'Self-test detectou codificação incompatível com Windows PowerShell 5.1.'
    }
    Write-Host 'Self-test do provisionador de credenciais: aprovado.' -ForegroundColor Green
    exit 0
}

foreach ($required in @($identity, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Arquivo administrativo ausente: $required"
    }
}

$endpointSecure = $null
$uazapiTokenSecure = $null
$resendKeySecure = $null
$emailFromSecure = $null
$endpoint = $null
$uazapiToken = $null
$resendKey = $null
$emailFrom = $null
$payload = $null
try {
    $Host.UI.RawUI.WindowTitle = 'Blindou - preparar credenciais UAZAPI e Resend'
    $status = (& ssh.exe @sshArgs $server `
        'sudo -n /usr/local/sbin/blindou-deployctl status' 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $status -notmatch '(?m)^provider_credential_staging_state=') {
        throw 'O controlador com o cofre de preparação ainda não está instalado no host.'
    }

    Write-Host 'Informe o endpoint HTTPS da UAZAPI e as três credenciais. Nada será ativado.' `
        -ForegroundColor Cyan
    $endpointSecure = Read-Host 'Endpoint HTTPS da UAZAPI' -AsSecureString
    $uazapiTokenSecure = Read-Host 'Token administrativo da UAZAPI' -AsSecureString
    $resendKeySecure = Read-Host 'Chave API da Resend' -AsSecureString
    $emailFromSecure = Read-Host 'E-mail remetente verificado na Resend' -AsSecureString

    $endpoint = (ConvertFrom-ProtectedValue $endpointSecure).Trim()
    $uazapiToken = (ConvertFrom-ProtectedValue $uazapiTokenSecure).Trim()
    $resendKey = (ConvertFrom-ProtectedValue $resendKeySecure).Trim()
    $emailFrom = (ConvertFrom-ProtectedValue $emailFromSecure).Trim()
    Test-ProviderInputs `
        -UazapiEndpoint $endpoint `
        -UazapiAdminToken $uazapiToken `
        -ResendApiKey $resendKey `
        -EmailFrom $emailFrom

    $payload = @(
        'schema=1',
        (ConvertTo-Base64Utf8 $endpoint),
        (ConvertTo-Base64Utf8 $uazapiToken),
        (ConvertTo-Base64Utf8 $resendKey),
        (ConvertTo-Base64Utf8 $emailFrom)
    ) -join "`n"
    $payload += "`n"
    Invoke-ClosedSshInput `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl stage-provider-credentials blindou-provider-credentials-staging' `
        -Payload $payload

    $endpoint = $null
    $uazapiToken = $null
    $resendKey = $null
    $emailFrom = $null
    $payload = $null
    & ssh.exe @sshArgs $server `
        'sudo -n /usr/local/sbin/blindou-deployctl verify-staged-provider-credentials'
    if ($LASTEXITCODE -ne 0) {
        throw 'A verificação posterior do cofre de preparação falhou.'
    }
    Write-Host 'Credenciais preparadas fora do runtime; UAZAPI e Resend continuam inativos.' `
        -ForegroundColor Green
}
finally {
    $endpoint = $null
    $uazapiToken = $null
    $resendKey = $null
    $emailFrom = $null
    $payload = $null
    if ($null -ne $endpointSecure) { $endpointSecure.Dispose() }
    if ($null -ne $uazapiTokenSecure) { $uazapiTokenSecure.Dispose() }
    if ($null -ne $resendKeySecure) { $resendKeySecure.Dispose() }
    if ($null -ne $emailFromSecure) { $emailFromSecure.Dispose() }
}
