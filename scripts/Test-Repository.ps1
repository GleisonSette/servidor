[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

& (Join-Path $root 'memory/tools/verify-index.ps1')

$forbiddenNames = @(
    '.env',
    'kubeconfig',
    'id_rsa',
    'id_ed25519'
)

$files = Get-ChildItem -LiteralPath $root -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }

foreach ($file in $files) {
    if ($forbiddenNames -contains $file.Name) {
        throw "Arquivo sensível não permitido: $($file.FullName)"
    }
    if ($file.Extension -in @('.key', '.pem', '.p12', '.pfx')) {
        throw "Material de chave não permitido: $($file.FullName)"
    }
}

$required = @(
    'LICENSE',
    'platform/base/kustomization.yaml',
    'platform/base/namespaces.yaml',
    'platform/base/project-spaces.yaml',
    'platform/base/service-exposure-policy.yaml',
    'platform/k3s/audit-policy.yaml',
    'platform/k3s/20-shared-lab.yaml',
    'operations/remote/maintenance-host.sh',
    'operations/remote/recover-dependent-services.sh',
    'operations/remote/verify-platform.sh'
)

foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative))) {
        throw "Arquivo obrigatório ausente: $relative"
    }
}

Write-Host 'Repositório verificado: memória íntegra e nenhum arquivo sensível conhecido.'
