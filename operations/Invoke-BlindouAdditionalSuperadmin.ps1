[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ReleaseId,

    [switch]$ConfirmCreation,
    [switch]$ResetPassword,
    [switch]$ConfirmReset,
    [switch]$ControllerOnly,
    [switch]$ControllerAlreadyUpdated,
    [switch]$PauseOnExit,
    [switch]$TransportSelfTest,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$utf8Encoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding
$targetIdentity = 'larissa-spezzia'
$targetEmail = 'larissa.spezzia@gmail.com'
$confirmation = 'blindou-additional-superadmin'
$resetConfirmation = 'blindou-reset-additional-superadmin-password'
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sshArgs = @(
    '-F', 'NUL',
    '-i', $identity,
    '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$knownHosts"
)
$archiveMembers = @(
    'operations/remote/blindou-deployctl',
    'operations/remote/blindou-deployctl.sudoers',
    'operations/remote/blindou-release-emergencyctl',
    'operations/remote/blindou-release-verify.py',
    'operations/remote/blindou-ghcr-pull-verify.py',
    'operations/remote/blindou-pagarme-plans.py',
    'operations/remote/blindou-dispatch-v3-jetstream.py',
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

    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToBase64String($bytes)
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
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
        $startInfo.StandardOutputEncoding = $utf8Encoding
        $startInfo.StandardErrorEncoding = $utf8Encoding
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw 'Não foi possível iniciar o SSH seguro.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.NewLine = "`n"
        $process.StandardInput.WriteLine($Payload)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($stdout) { Write-Host $stdout.TrimEnd() }
        if ($process.ExitCode -eq 0) { return }
        if ($process.ExitCode -ne 2) {
            if ($stderr) { Write-Host $stderr.TrimEnd() -ForegroundColor Red }
            throw 'A operação fechada no servidor falhou.'
        }
        if ($attempt -eq 12) {
            throw 'A operação não obteve o lock do controlador em um minuto.'
        }
        Write-Host 'O coletor de métricas está usando o controlador; nova tentativa em 5 segundos.' `
            -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

function Install-ClosedController {
    Import-Module (Join-Path $PSScriptRoot 'Blindou.SudoBootstrap.psm1') -Force

    $operationId = [guid]::NewGuid().ToString('N')
    $remoteRoot = "/home/apiadmin/blindou-platform-bootstrap-additional-superadmin-$operationId"
    $remoteArchive = "/home/apiadmin/blindou-platform-bootstrap-additional-superadmin-$operationId.tar.gz"
    $temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $temporaryRoot = [IO.Path]::GetFullPath((
        Join-Path $temporaryBase ("blindou-additional-superadmin-$operationId")
    ))
    if (-not $temporaryRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Diretório temporário escapou da raiz esperada.'
    }
    $archive = Join-Path $temporaryRoot 'controller.tar.gz'

    try {
        [void](New-Item -ItemType Directory -Path $temporaryRoot)
        foreach ($member in $archiveMembers) {
            $localPath = Join-Path $repositoryRoot $member
            if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
                throw "Artefato local ausente: $member"
            }
        }
        & tar.exe -czf $archive -C $repositoryRoot @archiveMembers
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $archive -PathType Leaf)) {
            throw 'Falha ao empacotar o controlador fechado.'
        }
        & scp.exe @sshArgs $archive "${server}:$remoteArchive"
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao enviar o controlador fechado.' }
        $remotePrepare = @"
install -d -m 0700 $remoteRoot
tar -xzf $remoteArchive -C $remoteRoot
rm -f -- $remoteArchive
chmod 0755 $remoteRoot/operations/remote/bootstrap-blindou-deployctl.sh
"@
        & ssh.exe @sshArgs $server $remotePrepare
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar o controlador no staging fechado.' }
        Write-Host 'Aguardando a janela de segurança do SSH antes da atualização.' `
            -ForegroundColor Yellow
        Start-Sleep -Seconds 45
        Invoke-BlindouSudoBootstrap `
            -ControllerSet DeployController `
            -SshArguments $sshArgs `
            -Server $server `
            -RemoteRoot $remoteRoot
        & ssh.exe @sshArgs $server "rm -rf -- $remoteRoot"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'O controlador foi instalado, mas o staging remoto não pôde ser limpo.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

if ($SelfTest) {
    if ($targetIdentity -cne 'larissa-spezzia' -or
        $targetEmail -cne 'larissa.spezzia@gmail.com' -or
        $confirmation -cne 'blindou-additional-superadmin' -or
        $resetConfirmation -cne 'blindou-reset-additional-superadmin-password') {
        throw 'Self-test encontrou identidade ou confirmação divergente.'
    }
    $fixture = 'BlindouSelfTest1!'
    $encodedFixture = ConvertTo-Base64Utf8 $fixture
    if ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedFixture)) -cne $fixture) {
        throw 'Self-test encontrou codificação incompatível.'
    }
    $fixture = $null
    $encodedFixture = $null
    Write-Host 'Self-test do superadmin adicional: aprovado.' -ForegroundColor Green
    exit 0
}

if ((@($ControllerOnly.IsPresent, $ControllerAlreadyUpdated.IsPresent,
        $TransportSelfTest.IsPresent) | Where-Object { $_ }).Count -gt 1) {
    throw 'ControllerOnly, ControllerAlreadyUpdated e TransportSelfTest são mutuamente exclusivos.'
}
if ($ResetPassword -and $ConfirmCreation) {
    throw 'ConfirmCreation não pode ser usado durante a redefinição.'
}
if (-not $ResetPassword -and $ConfirmReset) {
    throw 'ConfirmReset exige ResetPassword.'
}
if (-not $ControllerOnly -and -not $TransportSelfTest) {
    if ($ResetPassword -and -not $ConfirmReset) {
        throw 'Informe -ConfirmReset somente após autorização explícita da redefinição.'
    }
    if (-not $ResetPassword -and -not $ConfirmCreation) {
        throw 'Informe -ConfirmCreation somente após autorização explícita da criação.'
    }
}

foreach ($required in @($identity, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Arquivo administrativo ausente: $required"
    }
}

if ($TransportSelfTest) {
    $transportFixture = 'QmxpbmRvdVRyYW5zcG9ydFRlc3QxIQ=='
    $remoteTransportCheck =
        "IFS= read -r value || exit 17; [ `"`$value`" = '$transportFixture' ] || exit 18"
    Invoke-ClosedSshInput -RemoteCommand $remoteTransportCheck -Payload $transportFixture
    $transportFixture = $null
    Write-Host 'Self-test do transporte protegido: aprovado.' -ForegroundColor Green
    exit 0
}

$password = $null
$passwordConfirmation = $null
$plainPassword = $null
$plainConfirmation = $null
$encodedPassword = $null
$loginBody = $null
$loginResponse = $null
$meBody = $null
$meResponse = $null
$operationError = $null

try {
    $Host.UI.RawUI.WindowTitle = if ($ResetPassword) {
        'Blindou - redefinir senha da Larissa'
    } else {
        'Blindou - segundo acesso superadmin'
    }
    if (-not $ControllerAlreadyUpdated) {
        Write-Host 'Atualizando o controlador fechado do Blindou.' -ForegroundColor Cyan
        Install-ClosedController
    }
    if ($ControllerOnly) {
        Invoke-RemoteDeployControl `
            -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl status' `
            -FailureMessage 'O controlador atualizado não retornou o estado esperado.'
        Write-Host 'Controlador fechado atualizado; nenhuma identidade foi criada.' `
            -ForegroundColor Green
        exit 0
    }

    $operationLabel = if ($ResetPassword) { 'redefinição' } else { 'criação' }
    Write-Host "Validando os gates antes da $operationLabel." -ForegroundColor Cyan
    Invoke-RemoteDeployControl `
        -RemoteCommand (
            'sudo -n /usr/local/sbin/blindou-deployctl verify-foundation && ' +
            'sudo -n /usr/local/sbin/blindou-deployctl verify-data && ' +
            'sudo -n /usr/local/sbin/blindou-hostctl verify'
        ) `
        -FailureMessage 'Os gates da fundação, dos dados ou do host não passaram.'

    Write-Host ''
    if ($ResetPassword) {
        Write-Host "Redefinição da senha de $targetEmail." -ForegroundColor Cyan
    } else {
        Write-Host "Criação do superadmin $targetEmail." -ForegroundColor Cyan
    }
    Write-Host 'A senha precisa ter pelo menos 12 caracteres, com maiúscula, minúscula, número e símbolo.' `
        -ForegroundColor Yellow
    $password = Read-Host 'Senha da Larissa' -AsSecureString
    $passwordConfirmation = Read-Host 'Repita a senha da Larissa' -AsSecureString
    $plainPassword = ConvertFrom-ProtectedValue $password
    $plainConfirmation = ConvertFrom-ProtectedValue $passwordConfirmation
    if ($plainPassword -cne $plainConfirmation) {
        throw 'As senhas digitadas não coincidem.'
    }
    if ($plainPassword.Length -lt 12 -or
        $plainPassword -cnotmatch '[A-Z]' -or
        $plainPassword -cnotmatch '[a-z]' -or
        $plainPassword -cnotmatch '[0-9]' -or
        $plainPassword -notmatch '[^A-Za-z0-9]') {
        throw 'A senha não atende à complexidade mínima informada.'
    }
    $plainConfirmation = $null
    $encodedPassword = ConvertTo-Base64Utf8 $plainPassword
    $closedCommand = if ($ResetPassword) {
        "sudo -n /usr/local/sbin/blindou-deployctl reset-additional-superadmin-password $ReleaseId $targetIdentity $resetConfirmation"
    } else {
        "sudo -n /usr/local/sbin/blindou-deployctl bootstrap-additional-superadmin $ReleaseId $targetIdentity $confirmation"
    }
    Invoke-ClosedSshInput `
        -RemoteCommand $closedCommand `
        -Payload $encodedPassword
    $encodedPassword = $null

    Write-Host 'Validando o login e a autoridade pela API pública.' -ForegroundColor Cyan
    $loginBody = @{
        query = 'mutation Login($email: String!, $password: String!) { login(email: $email, password: $password) { challengeId tokens { accessToken refreshToken deploymentLane } } }'
        variables = @{
            email = $targetEmail
            password = $plainPassword
        }
    } | ConvertTo-Json -Compress -Depth 8
    $loginResponse = Invoke-RestMethod `
        -Uri 'https://api.blindou.com/graphql' `
        -Method Post `
        -ContentType 'application/json' `
        -Body $loginBody `
        -TimeoutSec 30
    if ($null -ne $loginResponse.errors -or
        [string]::IsNullOrWhiteSpace($loginResponse.data.login.tokens.accessToken) -or
        [string]::IsNullOrWhiteSpace($loginResponse.data.login.tokens.refreshToken)) {
        throw 'O login público não retornou a sessão esperada.'
    }
    $meBody = @{ query = 'query Me { me { email isSuperAdmin } }' } |
        ConvertTo-Json -Compress -Depth 4
    $headers = @{ Authorization = "Bearer $($loginResponse.data.login.tokens.accessToken)" }
    $meResponse = Invoke-RestMethod `
        -Uri 'https://api.blindou.com/graphql' `
        -Method Post `
        -ContentType 'application/json' `
        -Headers $headers `
        -Body $meBody `
        -TimeoutSec 30
    if ($null -ne $meResponse.errors -or
        $meResponse.data.me.email -cne $targetEmail -or
        $meResponse.data.me.isSuperAdmin -ne $true) {
        throw 'A sessão pública não confirmou a autoridade super_admin esperada.'
    }
    $headers = $null
    $meResponse = $null
    $meBody = $null
    $loginResponse = $null
    $loginBody = $null
    $plainPassword = $null

    Invoke-RemoteDeployControl `
        -RemoteCommand (
            'sudo -n /usr/local/sbin/blindou-deployctl verify-foundation && ' +
            'sudo -n /usr/local/sbin/blindou-deployctl verify-data && ' +
            'sudo -n /usr/local/sbin/apiwpp-deployctl verify && ' +
            'sudo -n /usr/local/sbin/blindou-hostctl verify'
        ) `
        -FailureMessage "Um gate final falhou depois da $operationLabel."

    Write-Host ''
    if ($ResetPassword) {
        Write-Host "Senha redefinida e acesso validado para $targetEmail." -ForegroundColor Green
    } else {
        Write-Host "Acesso criado e validado para $targetEmail." -ForegroundColor Green
    }
    Write-Host 'Acesse: https://app.blindou.com' -ForegroundColor Green
}
catch {
    $operationError = $_
    Write-Host ''
    Write-Host "A operação falhou: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    $password = $null
    $passwordConfirmation = $null
    $plainPassword = $null
    $plainConfirmation = $null
    $encodedPassword = $null
    $loginBody = $null
    $loginResponse = $null
    $meBody = $null
    $meResponse = $null
}

if ($PauseOnExit) {
    [void](Read-Host 'Pressione Enter para fechar esta janela')
}
if ($null -ne $operationError) {
    exit 1
}
