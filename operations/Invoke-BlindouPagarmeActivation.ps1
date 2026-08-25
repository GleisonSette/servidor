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

$confirmation = Read-Host (
    "Digite ATIVAR PAGARME para habilitar cobrança live na release $ReleaseId"
)
if ($confirmation -cne 'ATIVAR PAGARME') {
    throw 'Ativação cancelada: a confirmação exata não foi informada.'
}

Write-Host 'Validando a credencial live antes da ativação.' -ForegroundColor Cyan
Invoke-RemoteDeployControl `
    -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl verify-pagarme-credential' `
    -FailureMessage 'A credencial live Pagar.me não passou na validação autenticada.'

Write-Host 'Ativando Pagar.me somente na release marcada como compatível.' -ForegroundColor Cyan
Invoke-RemoteDeployControl `
    -RemoteCommand "sudo -n /usr/local/sbin/blindou-deployctl activate-pagarme-runtime $ReleaseId blindou-pagarme-runtime" `
    -FailureMessage 'A ativação do Pagar.me falhou; consulte o diagnóstico fechado do controlador.'

Write-Host 'Validando o estado final sem exibir segredos.' -ForegroundColor Cyan
Invoke-RemoteDeployControl `
    -RemoteCommand 'sudo -n /usr/local/sbin/blindou-deployctl status' `
    -FailureMessage 'A leitura do estado final do Pagar.me falhou.'

Write-Host 'Pagar.me live ativado. UAZAPI e Resend continuam desabilitados.' `
    -ForegroundColor Green
