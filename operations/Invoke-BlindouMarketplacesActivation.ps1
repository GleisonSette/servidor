[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ReleaseId,

    [switch]$ConfirmActivation
)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmActivation) {
    throw 'Informe -ConfirmActivation somente após autorização explícita da ativação.'
}

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

foreach ($required in @($identity, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Arquivo administrativo ausente: $required"
    }
}

Write-Host 'Ativando o cofre interno e a conexão oficial da Shopee.' -ForegroundColor Cyan
Invoke-RemoteDeployControl `
    -RemoteCommand "sudo -n /usr/local/sbin/blindou-deployctl activate-marketplaces-runtime $ReleaseId blindou-marketplaces-runtime" `
    -FailureMessage 'A ativação da Shopee falhou; o controlador tentou restaurar o estado anterior.'

Write-Host 'Validando o estado final sem exibir segredos.' -ForegroundColor Cyan
Invoke-RemoteDeployControl `
    -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl verify-marketplaces-runtime' `
    -FailureMessage 'O runtime da Shopee não passou na verificação final.'
Invoke-RemoteDeployControl `
    -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl status' `
    -FailureMessage 'A leitura do estado final de Marketplaces falhou.'

Write-Host 'Shopee pronta para receber AppID e App Secret diretamente no Blindou.' `
    -ForegroundColor Green
