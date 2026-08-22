[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ReleaseId
)

$ErrorActionPreference = 'Stop'
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$backupBase = Join-Path $env:LOCALAPPDATA 'blindou\backups'
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
        if ($exitCode -eq 0) {
            return
        }
        if ($exitCode -ne 2) {
            throw $FailureMessage
        }
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
        $Payload | & ssh.exe @sshArgs $server $RemoteCommand
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            return
        }
        if ($exitCode -ne 2) {
            throw 'A operação fechada no servidor falhou.'
        }
        if ($attempt -eq 12) {
            throw 'A operação fechada não obteve o lock do controlador em um minuto.'
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

$password = $null
$passwordConfirmation = $null
$plainPassword = $null
$loginBody = $null
$loginResponse = $null

try {
    $Host.UI.RawUI.WindowTitle = 'Blindou - acesso para revisão da interface'
    Write-Host 'Implantação do núcleo do Blindou para revisão da interface.' -ForegroundColor Cyan
    Write-Host 'UAZAPI, Resend e Pagar.me permanecerão desabilitados até a aprovação da UI.' -ForegroundColor Yellow
    Invoke-RemoteDeployControl `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl provision-ui-review-runtime blindou-ui-review-runtime' `
        -FailureMessage 'Falha ao preparar o núcleo sem provedores externos.'

    Write-Host 'Criando e exportando o backup criptografado anterior às migrations.' -ForegroundColor Cyan
    Invoke-RemoteDeployControl `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl backup-database blindou-database-backup' `
        -FailureMessage 'Falha ao criar o backup.'
    Invoke-RemoteDeployControl `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl export-latest-backup' `
        -FailureMessage 'Falha ao exportar o backup.'
    $status = Invoke-RemoteDeployControl `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl status' `
        -FailureMessage 'Falha ao consultar o backup mais recente.'
    $backupLine = $status | Where-Object { $_ -match '^latest_encrypted_backup=blindou-[0-9]{8}T[0-9]{6}Z$' }
    if (@($backupLine).Count -ne 1) { throw 'O status não retornou um backup único.' }
    $backupId = ($backupLine -split '=', 2)[1]
    $localBackup = Join-Path $backupBase $backupId
    if (Test-Path -LiteralPath $localBackup) {
        throw "A pasta local do backup já existe: $localBackup"
    }
    [void](New-Item -ItemType Directory -Path $localBackup -Force)
    foreach ($file in @("$backupId.dump.cms", "$backupId.manifest", 'recovery-recipient.crt')) {
        & scp.exe @sshArgs "${server}:/home/apiadmin/blindou-backup-outbox/$backupId/$file" $localBackup
        if ($LASTEXITCODE -ne 0) { throw "Falha ao baixar o artefato offsite: $file" }
    }
    $manifestPath = Join-Path $localBackup "$backupId.manifest"
    $encryptedPath = Join-Path $localBackup "$backupId.dump.cms"
    $manifest = Get-Content -LiteralPath $manifestPath
    $shaLine = $manifest | Where-Object { $_ -match '^encrypted_sha256=[0-9a-f]{64}$' }
    $sizeLine = $manifest | Where-Object { $_ -match '^encrypted_size=[0-9]+$' }
    if (@($shaLine).Count -ne 1 -or @($sizeLine).Count -ne 1) {
        throw 'O manifesto offsite possui campos ausentes ou duplicados.'
    }
    $expectedSha = ($shaLine -split '=', 2)[1]
    $expectedSize = [int64](($sizeLine -split '=', 2)[1])
    $actualSha = (Get-FileHash -LiteralPath $encryptedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $actualSize = (Get-Item -LiteralPath $encryptedPath).Length
    if ($actualSha -cne $expectedSha -or $actualSize -ne $expectedSize) {
        throw 'A cópia offsite diverge do manifesto assinado pelo host.'
    }
    Invoke-RemoteDeployControl `
        -RemoteCommand "sudo -n /usr/local/sbin/blindou-deployctl confirm-offsite-backup $backupId $expectedSha blindou-offsite-backup" `
        -FailureMessage 'Falha ao registrar a cópia offsite verificada.'

    Write-Host 'Liberando os gates somente para a candidata assinada e iniciando migrations/deploy.' -ForegroundColor Cyan
    Invoke-RemoteDeployControl `
        -RemoteCommand "sudo -n /usr/local/sbin/blindou-deployctl activate-release-gates $ReleaseId blindou-release-gates" `
        -FailureMessage 'Falha ao liberar os gates da candidata assinada.'
    Invoke-RemoteDeployControl `
        -RemoteCommand "sudo -n /usr/local/sbin/blindou-deployctl apply $ReleaseId" `
        -FailureMessage 'Migration ou deploy falhou; o controlador executou a contenção prevista.'

    Write-Host ''
    Write-Host 'Criação do superadmin gleisonsette@gmail.com.' -ForegroundColor Cyan
    Write-Host 'A senha precisa ter pelo menos 12 caracteres, com maiúscula, minúscula, número e símbolo.' -ForegroundColor Yellow
    $password = Read-Host 'Senha do superadmin' -AsSecureString
    $passwordConfirmation = Read-Host 'Repita a senha do superadmin' -AsSecureString
    $plainPassword = ConvertFrom-ProtectedValue $password
    $plainConfirmation = ConvertFrom-ProtectedValue $passwordConfirmation
    if ($plainPassword -cne $plainConfirmation) {
        throw 'As senhas digitadas não coincidem.'
    }
    $plainConfirmation = $null
    Invoke-ClosedSshInput `
        -RemoteCommand "sudo -n /usr/local/sbin/blindou-deployctl bootstrap-superadmin $ReleaseId blindou-bootstrap-superadmin" `
        -Payload (ConvertTo-Base64Utf8 $plainPassword)

    Write-Host 'Validando a autenticação real pela borda pública, sem exibir os tokens.' -ForegroundColor Cyan
    $loginBody = @{
        query = 'mutation Login($email: String!, $password: String!) { login(email: $email, password: $password) { challengeId tokens { accessToken refreshToken deploymentLane } } }'
        variables = @{
            email = 'gleisonsette@gmail.com'
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
    $loginResponse = $null
    $loginBody = $null
    $plainPassword = $null

    foreach ($verification in @('verify-foundation', 'verify-data', 'verify-backup')) {
        Invoke-RemoteDeployControl `
            -RemoteCommand "sudo -n /usr/local/sbin/blindou-deployctl $verification" `
            -FailureMessage "A verificação final $verification falhou."
    }
    & ssh.exe @sshArgs $server `
        'sudo -n /usr/local/sbin/apiwpp-deployctl verify && sudo -n /usr/local/sbin/blindou-hostctl verify'
    if ($LASTEXITCODE -ne 0) { throw 'O gate final do host ou do apiwpp falhou.' }
    Invoke-RemoteDeployControl `
        -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl status' `
        -FailureMessage 'A leitura do estado final do Blindou falhou.'
    Write-Host ''
    Write-Host 'Implantação concluída. O login público do superadmin foi validado.' -ForegroundColor Green
    Write-Host 'Acesse: https://app.blindou.com' -ForegroundColor Green
    Write-Host "Backup offsite verificado: $localBackup" -ForegroundColor Green
}
finally {
    $password = $null
    $passwordConfirmation = $null
    $plainPassword = $null
    $loginBody = $null
    $loginResponse = $null
}

Read-Host 'Pressione ENTER para fechar'
