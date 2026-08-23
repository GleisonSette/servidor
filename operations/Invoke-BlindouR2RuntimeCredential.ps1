[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$remoteRoot = '/home/apiadmin/blindou-platform-bootstrap-r2-runtime'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
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

$files = @(
    @{ Local = 'operations/remote/blindou-deployctl'; Remote = 'operations/remote/' },
    @{ Local = 'operations/remote/blindou-deployctl.sudoers'; Remote = 'operations/remote/' },
    @{ Local = 'operations/remote/blindou-release-emergencyctl'; Remote = 'operations/remote/' },
    @{ Local = 'operations/remote/blindou-release-verify.py'; Remote = 'operations/remote/' },
    @{ Local = 'operations/remote/blindou-ghcr-pull-verify.py'; Remote = 'operations/remote/' },
    @{ Local = 'operations/remote/blindou-platform-metrics'; Remote = 'operations/remote/' },
    @{ Local = 'operations/remote/blindou-platform-metrics.service'; Remote = 'operations/remote/' },
    @{ Local = 'operations/remote/blindou-platform-metrics.timer'; Remote = 'operations/remote/' },
    @{ Local = 'operations/remote/blindou-release-allowed-signers'; Remote = 'operations/remote/' },
    @{ Local = 'operations/remote/blindou-backup-recipient.crt'; Remote = 'operations/remote/' },
    @{ Local = 'operations/remote/bootstrap-blindou-deployctl.sh'; Remote = 'operations/remote/' },
    @{ Local = 'platform/blindou/00-namespaces.yaml'; Remote = 'platform/blindou/' },
    @{ Local = 'platform/blindou/10-quarantine.yaml'; Remote = 'platform/blindou/' },
    @{ Local = 'platform/blindou/15-edge-connector-gate.yaml'; Remote = 'platform/blindou/' },
    @{ Local = 'platform/blindou/16-edge-connector-runtime.yaml'; Remote = 'platform/blindou/' },
    @{ Local = 'platform/blindou/20-production-workload-policy.yaml'; Remote = 'platform/blindou/' },
    @{ Local = 'platform/base/service-exposure-policy.yaml'; Remote = 'platform/base/' }
)

$accessKeySecure = $null
$secretKeySecure = $null
$accessKey = $null
$secretKey = $null
$payload = $null
try {
    $Host.UI.RawUI.WindowTitle = 'Blindou - credencial R2 do runtime'
    Write-Host 'Atualizando o controlador fechado do Blindou.' -ForegroundColor Cyan
    & ssh.exe @sshArgs $server (
        "install -d -m 0700 " +
        "$remoteRoot/operations/remote $remoteRoot/platform/blindou $remoteRoot/platform/base"
    )
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar o diretório remoto.' }
    foreach ($file in $files) {
        $localPath = Join-Path $repositoryRoot $file.Local
        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            throw "Artefato local ausente: $($file.Local)"
        }
        & scp.exe @sshArgs $localPath "${server}:$remoteRoot/$($file.Remote)"
        if ($LASTEXITCODE -ne 0) { throw "Falha ao enviar $($file.Local)." }
    }
    Invoke-BlindouSudoBootstrap `
        -ControllerSet DeployController `
        -SshArguments $sshArgs `
        -Server $server `
        -RemoteRoot $remoteRoot

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

    Invoke-RemoteDeployControl `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl provision-ui-review-runtime blindou-ui-review-runtime' `
        -FailureMessage 'Falha ao republicar o runtime de revisão com R2.'
    Invoke-RemoteDeployControl `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl verify-r2-runtime-credential' `
        -FailureMessage 'A verificação final do R2 falhou.'
    Write-Host ''
    Write-Host 'R2 validado e runtime técnico republicado. Volte ao Codex.' -ForegroundColor Green
}
finally {
    $accessKey = $null
    $secretKey = $null
    $payload = $null
    if ($null -ne $accessKeySecure) { $accessKeySecure.Dispose() }
    if ($null -ne $secretKeySecure) { $secretKeySecure.Dispose() }
}

Read-Host 'Pressione ENTER para fechar'
