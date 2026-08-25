[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$RotateWebhook,
    [switch]$ControllerOnly
)

$ErrorActionPreference = 'Stop'
$utf8Encoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$remoteRoot = '/home/apiadmin/blindou-platform-bootstrap-pagarme'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$archiveDirectory = Join-Path $env:LOCALAPPDATA 'blindou\bootstrap'
$archive = Join-Path $archiveDirectory 'blindou-pagarme-bootstrap.tar.gz'
$webhookBaseUrl = 'https://api.blindou.com/webhooks/pagarme/'
Import-Module (Join-Path $PSScriptRoot 'Blindou.SudoBootstrap.psm1') -Force
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

function New-WebhookSecret {
    $bytes = [byte[]]::new(32)
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }
    finally {
        $generator.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
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
            throw 'Provisionamento fechado da credencial Pagar.me falhou.'
        }
        if ($attempt -eq 12) {
            throw 'O controlador permaneceu ocupado por um minuto.'
        }
        Write-Host 'O coletor de métricas está usando o controlador; nova tentativa em 5 segundos.' `
            -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

function Get-ControllerStatusWithLockRetry {
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $status = (& ssh.exe @sshArgs $server `
            'sudo -n /usr/local/sbin/blindou-deployctl status' 2>$null) -join "`n"
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) { return $status }
        if ($exitCode -ne 2) { return '' }
        if ($attempt -eq 12) {
            throw 'O controlador permaneceu ocupado por um minuto durante a verificação inicial.'
        }
        Write-Host 'O coletor de métricas está usando o controlador; nova verificação em 5 segundos.' `
            -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

if ((@($SelfTest.IsPresent, $RotateWebhook.IsPresent, $ControllerOnly.IsPresent) |
        Where-Object { $_ }).Count -gt 1) {
    throw 'SelfTest, RotateWebhook e ControllerOnly são opções mutuamente exclusivas.'
}
if ($SelfTest) {
    $secretFixture = New-WebhookSecret
    if ($secretFixture -cnotmatch '^[A-Za-z0-9_-]{43}$') {
        throw 'Self-test não gerou segredo de webhook com 32 bytes em base64url.'
    }
    $expectedPortuguese = -join ([char[]](112, 114, 111, 100, 117, 231, 227, 111))
    if ('produção' -cne $expectedPortuguese) {
        throw 'Self-test detectou codificação incompatível com Windows PowerShell 5.1.'
    }
    $processEncodingFixture = [Diagnostics.ProcessStartInfo]::new()
    $processEncodingFixture.StandardOutputEncoding = $utf8Encoding
    $processEncodingFixture.StandardErrorEncoding = $utf8Encoding
    Write-Host 'Self-test da credencial Pagar.me: aprovado.' -ForegroundColor Green
    exit 0
}

foreach ($required in @($identity, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Arquivo administrativo ausente: $required"
    }
}

$archiveMembers = @(
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

$secretKeySecure = $null
$secretKey = $null
$webhookSecret = $null
$webhookUrl = $null
$payload = $null
$clipboardContainsWebhook = $false
$operationFailed = $false
try {
    $Host.UI.RawUI.WindowTitle = 'Blindou - credencial Pagar.me live'
    $controllerStatus = Get-ControllerStatusWithLockRetry
    $controllerReady = $controllerStatus -match '(?m)^pagarme_credential_state='
    if ($RotateWebhook -or $ControllerOnly) { $controllerReady = $false }
    if ($controllerReady) {
        Write-Host 'Controlador Pagar.me já instalado no host.' -ForegroundColor Green
    }
    else {
        Write-Host 'Atualizando o controlador fechado do Blindou.' -ForegroundColor Cyan
        foreach ($member in $archiveMembers) {
            $localPath = Join-Path $repositoryRoot $member
            if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
                throw "Artefato local ausente: $member"
            }
        }
        if (-not (Test-Path -LiteralPath $archiveDirectory -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $archiveDirectory -Force)
        }
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
        & tar.exe -czf $archive -C $repositoryRoot @archiveMembers
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $archive -PathType Leaf)) {
            throw 'Falha ao criar o pacote fechado do controlador.'
        }
        & scp.exe @sshArgs $archive "${server}:/home/apiadmin/blindou-pagarme-bootstrap.tar.gz"
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao enviar o pacote fechado do controlador.' }
        $remotePrepare = @"
install -d -m 0700 $remoteRoot
tar -xzf /home/apiadmin/blindou-pagarme-bootstrap.tar.gz -C $remoteRoot
rm -f -- /home/apiadmin/blindou-pagarme-bootstrap.tar.gz
chmod 0755 $remoteRoot/operations/remote/bootstrap-blindou-deployctl.sh
"@
        & ssh.exe @sshArgs $server $remotePrepare
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar o pacote remoto.' }
        Write-Host 'Aguardando a janela de segurança do SSH antes do bootstrap.' -ForegroundColor Yellow
        Start-Sleep -Seconds 45
        Invoke-BlindouSudoBootstrap `
            -ControllerSet DeployController `
            -SshArguments $sshArgs `
            -Server $server `
            -RemoteRoot $remoteRoot
    }

    if ($ControllerOnly) {
        Write-Host 'Controlador fechado atualizado; credenciais e runtime não foram alterados.' `
            -ForegroundColor Green
        return
    }

    if ($RotateWebhook) {
        $webhookSecret = New-WebhookSecret
        $payload = @(
            'schema=1',
            (ConvertTo-Base64Utf8 $webhookSecret)
        ) -join "`n"
        $payload += "`n"
        Invoke-ClosedSshInput `
            -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl rotate-pagarme-webhook-secret blindou-pagarme-webhook-rotation' `
            -Payload $payload
        $payload = $null

        $webhookUrl = $webhookBaseUrl + $webhookSecret
        Set-Clipboard -Value $webhookUrl
        $clipboardContainsWebhook = $true
        Write-Host ''
        Write-Host 'Nova URL secreta do webhook copiada para a área de transferência.' -ForegroundColor Cyan
        Write-Host 'Aguardando o cadastro no painel Pagar.me; o valor não será exibido.' -ForegroundColor Yellow
        $clipboardConfirmation = Read-Host 'Depois do cadastro, pressione ENTER para limpar a área de transferência' -AsSecureString
        if ($null -ne $clipboardConfirmation) { $clipboardConfirmation.Dispose() }
        Set-Clipboard -Value ' '
        $clipboardContainsWebhook = $false
        $webhookUrl = $null
        $webhookSecret = $null
        Write-Host 'Webhook rotacionado e área de transferência limpa. O runtime não foi alterado.' `
            -ForegroundColor Green
        return
    }

    Write-Host ''
    Write-Host 'Copie a secret key de produção no painel Pagar.me.' -ForegroundColor Cyan
    Write-Host 'O valor ficará mascarado e não será salvo nesta estação.' -ForegroundColor Yellow
    $secretKeySecure = Read-Host 'Cole a secret key de produção' -AsSecureString
    $secretKey = (ConvertFrom-ProtectedValue $secretKeySecure).Trim()
    if ($secretKey -cnotmatch '^sk_[A-Za-z0-9]{16,509}$' -or $secretKey.StartsWith('sk_test_', [StringComparison]::Ordinal)) {
        throw 'A secret key não possui o formato de produção sk_* esperado ou pertence ao sandbox.'
    }
    $webhookSecret = New-WebhookSecret
    $payload = @(
        'schema=1',
        (ConvertTo-Base64Utf8 $secretKey),
        (ConvertTo-Base64Utf8 $webhookSecret)
    ) -join "`n"
    $payload += "`n"
    Invoke-ClosedSshInput `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl provision-pagarme-credential blindou-pagarme-credential' `
        -Payload $payload
    $secretKey = $null
    $payload = $null

    $webhookUrl = $webhookBaseUrl + $webhookSecret
    Set-Clipboard -Value $webhookUrl
    $clipboardContainsWebhook = $true
    Write-Host ''
    Write-Host 'A URL secreta do webhook foi copiada para a área de transferência.' -ForegroundColor Cyan
    Write-Host 'Cole-a diretamente no painel Pagar.me; não envie a URL ao chat.' -ForegroundColor Yellow
    $clipboardConfirmation = Read-Host 'Depois de cadastrar o webhook, pressione ENTER para limpar a área de transferência' -AsSecureString
    if ($null -ne $clipboardConfirmation) { $clipboardConfirmation.Dispose() }
    Set-Clipboard -Value ' '
    $clipboardContainsWebhook = $false
    $webhookUrl = $null
    $webhookSecret = $null
    Write-Host 'Credencial validada e guardada. O runtime e os workloads não foram alterados.' `
        -ForegroundColor Green
}
catch {
    $operationFailed = $true
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'A operação foi interrompida sem tentar contornar a falha.' -ForegroundColor Red
}
finally {
    if ($clipboardContainsWebhook) {
        try { Set-Clipboard -Value ' ' } catch { }
    }
    $secretKey = $null
    $webhookSecret = $null
    $webhookUrl = $null
    $payload = $null
    if ($null -ne $secretKeySecure) { $secretKeySecure.Dispose() }
    if (Test-Path -LiteralPath $archive -PathType Leaf) {
        Remove-Item -LiteralPath $archive -Force
    }
}

Read-Host 'Pressione ENTER para fechar'
if ($operationFailed) { exit 1 }
