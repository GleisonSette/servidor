[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$remoteRoot = '/home/apiadmin/blindou-platform-bootstrap-r2-runtime'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$archiveDirectory = Join-Path $env:LOCALAPPDATA 'blindou\bootstrap'
$archive = Join-Path $archiveDirectory 'blindou-r2-runtime-bootstrap.tar.gz'
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

function Invoke-RemoteDeployControl {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteCommand,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    for ($attempt = 1; $attempt -le 12; $attempt++) {
        & ssh.exe @sshArgs $server $RemoteCommand
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) { return }
        if ($exitCode -ne 2) { throw $FailureMessage }
        if ($attempt -eq 12) {
            throw "$FailureMessage O controlador permaneceu ocupado por um minuto."
        }
        Write-Host 'O coletor de métricas está usando o controlador; nova tentativa em 5 segundos.' `
            -ForegroundColor Yellow
        Start-Sleep -Seconds 5
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
            throw 'Provisionamento fechado da credencial R2 falhou.'
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

$archiveMembers = @(
    'operations/remote/blindou-deployctl',
    'operations/remote/blindou-deployctl.sudoers',
    'operations/remote/blindou-release-emergencyctl',
    'operations/remote/blindou-release-verify.py',
    'operations/remote/blindou-ghcr-pull-verify.py',
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

$accessKeySecure = $null
$secretKeySecure = $null
$accessKey = $null
$secretKey = $null
$payload = $null
$operationFailed = $false
try {
    $Host.UI.RawUI.WindowTitle = 'Blindou - credencial R2 do runtime'
    $controllerStatus = (& ssh.exe @sshArgs $server `
        'sudo -n /usr/local/sbin/blindou-deployctl status' 2>$null) -join "`n"
    $controllerReady = $LASTEXITCODE -eq 0 -and
        $controllerStatus -match '(?m)^r2_runtime_credential_state='
    if ($controllerReady) {
        Write-Host 'Controlador R2 já instalado e autenticado no host.' -ForegroundColor Green
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
        & scp.exe @sshArgs $archive "${server}:/home/apiadmin/blindou-r2-runtime-bootstrap.tar.gz"
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao enviar o pacote fechado do controlador.' }
        $remotePrepare = @"
install -d -m 0700 $remoteRoot
tar -xzf /home/apiadmin/blindou-r2-runtime-bootstrap.tar.gz -C $remoteRoot
rm -f -- /home/apiadmin/blindou-r2-runtime-bootstrap.tar.gz
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

    Write-Host ''
    Write-Host 'Na aba da Cloudflare, copie primeiro “ID da chave de acesso”.' -ForegroundColor Cyan
    Write-Host 'Os valores ficarão mascarados e não serão salvos neste computador.' -ForegroundColor Yellow
    $accessKeySecure = Read-Host 'Cole o ID da chave de acesso' -AsSecureString
    Write-Host 'Agora copie “Chave de acesso secreta” na mesma página.' -ForegroundColor Cyan
    $secretKeySecure = Read-Host 'Cole a chave de acesso secreta' -AsSecureString
    $accessKey = (ConvertFrom-ProtectedValue $accessKeySecure).Trim()
    $secretKey = (ConvertFrom-ProtectedValue $secretKeySecure).Trim()
    if ($accessKey -notmatch '^[A-Za-z0-9]{20,128}$') {
        throw 'O ID da chave de acesso não possui o formato esperado.'
    }
    if ($secretKey -notmatch '^[A-Za-z0-9]{32,256}$') {
        throw 'A chave secreta não possui o formato esperado.'
    }
    $payload = @(
        'schema=1',
        (ConvertTo-Base64Utf8 $accessKey),
        (ConvertTo-Base64Utf8 $secretKey)
    ) -join "`n"
    $payload += "`n"
    Invoke-ClosedSshInput `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl provision-r2-runtime-credential blindou-r2-runtime-credential' `
        -Payload $payload
    $accessKey = $null
    $secretKey = $null
    $payload = $null

    Write-Host 'Aguardando a janela de segurança do SSH antes de republicar o runtime.' `
        -ForegroundColor Yellow
    Start-Sleep -Seconds 20
    Invoke-RemoteDeployControl `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl provision-ui-review-runtime blindou-ui-review-runtime' `
        -FailureMessage 'Falha ao republicar o runtime de revisão com R2.'
    Write-Host ''
    Write-Host 'R2 validado e runtime técnico republicado. Volte ao Codex.' -ForegroundColor Green
}
catch {
    $operationFailed = $true
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'A operação foi interrompida sem tentar contornar a falha.' -ForegroundColor Red
}
finally {
    $accessKey = $null
    $secretKey = $null
    $payload = $null
    if ($null -ne $accessKeySecure) { $accessKeySecure.Dispose() }
    if ($null -ne $secretKeySecure) { $secretKeySecure.Dispose() }
    if (Test-Path -LiteralPath $archive -PathType Leaf) {
        Remove-Item -LiteralPath $archive -Force
    }
}

Read-Host 'Pressione ENTER para fechar'
if ($operationFailed) { exit 1 }
