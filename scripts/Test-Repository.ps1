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
        $rootEnv = Join-Path $root '.env'
        if ($file.Name -eq '.env' -and $file.FullName -eq $rootEnv) {
            & git -C $root check-ignore -q -- .env
            if ($LASTEXITCODE -ne 0) {
                throw 'O .env local permitido por D025 não está protegido pelo gitignore.'
            }
            continue
        }
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
    'platform/blindou/20-production-workload-policy.yaml',
    'platform/blindou-data/kustomization.yaml',
    'platform/saferwpp/foundation.yaml',
    'platform/saferwpp/backup-preflight.schema.json',
    'platform/saferwpp/kustomization.yaml',
    'platform/security/blindou-edge-policy.yaml',
    'platform/k3s/audit-policy.yaml',
    'platform/k3s/20-shared-lab.yaml',
    'operations/remote/maintenance-host.sh',
    'operations/remote/recover-dependent-services.sh',
    'operations/remote/verify-platform.sh',
    'operations/remote/verify-blindou-isolation.sh',
    'operations/remote/verify-saferwpp-foundation-artifacts.py',
    'operations/Dre.SudoBootstrap.psm1',
    'operations/Invoke-DreControllerBootstrap.ps1',
    'operations/remote/dre-deployctl',
    'operations/remote/dre-deployctl.sudoers',
    'operations/remote/dre-deployctl.logrotate',
    'operations/remote/dre-release-verify.py',
    'operations/remote/dre-secret-material.py',
    'operations/remote/dre-validation-material.py',
    'operations/remote/dre-restore-render.py',
    'operations/remote/dre-kube-identityctl',
    'operations/remote/bootstrap-dre-deployctl.sh',
    'operations/remote/verify-dre-controller-artifacts.py',
    'platform/dre/controller-foundation.yaml',
    'platform/dre/validation-access.yaml',
    'platform/dre/monitoring/prometheus-alerts.yaml',
    'runbooks/dre-k3s.md',
    'operations/Blindou.SudoBootstrap.psm1',
    'operations/Invoke-BlindouDataControllerBootstrap.ps1',
    'operations/Invoke-BlindouDataPullProof.ps1',
    'operations/remote/blindou-datactl',
    'operations/remote/blindou-datactl.sudoers',
    'operations/remote/blindou-data-ghcr-pull-verify.py',
    'operations/remote/bootstrap-blindou-datactl.sh',
    'operations/remote/verify-blindou-data-artifacts.py',
    'runbooks/blindou-contencao.md'
)

foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative))) {
        throw "Arquivo obrigatório ausente: $relative"
    }
}

$dreBootstrap = Get-Content -Raw -LiteralPath (
    Join-Path $root 'operations/Invoke-DreControllerBootstrap.ps1'
)
foreach ($invariant in @(
    'apiadmin@192.168.100.59',
    'dre-controller-bootstrap-4902604dad96-20260830T215253Z',
    'e9037fa049f2760426002a8c7ad8949d9d6f8154d11407cc7e56306051822bd4',
    '4902604dad96d9b07f4010308d30e3815cb4e76446855d925079be0e3b922ce9',
    'StrictHostKeyChecking=yes'
)) {
    if (-not $dreBootstrap.Contains($invariant)) {
        throw "Orquestrador DRE diverge do bundle aprovado: $invariant"
    }
}

$dataBootstrap = Get-Content -Raw -LiteralPath (
    Join-Path $root 'operations/Invoke-BlindouDataControllerBootstrap.ps1'
)
if ($dataBootstrap -cnotmatch '\$postInstall = @''\r?\nset -eu\r?\n') {
    throw 'O pós-bootstrap de dados não propaga falhas remotas.'
}
$dataPullProof = Get-Content -Raw -LiteralPath (
    Join-Path $root 'operations/Invoke-BlindouDataPullProof.ps1'
)
if (-not $dataPullProof.Contains('$matchingImages = @(') -or
    -not $dataPullProof.Contains('if ($matchingImages.Count -ne 1)')) {
    throw 'A prova de pull não preserva cardinalidade no StrictMode.'
}
$dataController = Get-Content -Raw -LiteralPath (
    Join-Path $root 'operations/remote/blindou-datactl'
)
if ($dataController.Contains(
    'local name="$1" release="$2" path="${RECEIPT_ROOT}/${name}.state"'
)) {
    throw 'O controlador expande name antes da atribuição sob nounset.'
}
if ($dataController -cnotmatch
    'local name="\$1" release="\$2" path\r?\n\s+path="\$\{RECEIPT_ROOT\}/\$\{name\}\.state"') {
    throw 'O caminho dos recibos não é derivado depois da atribuição de name.'
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $pythonCommand) {
    $pythonCommand = Get-Command python3 -ErrorAction Stop
}
& $pythonCommand.Source -B (Join-Path $root 'operations/remote/verify-saferwpp-foundation-artifacts.py')
& $pythonCommand.Source -B (Join-Path $root 'operations/remote/verify-dre-controller-artifacts.py')
& $pythonCommand.Source -B (Join-Path $root 'operations/remote/test-dre-release-verify.py')
& $pythonCommand.Source -B (Join-Path $root 'operations/remote/test-dre-secret-material.py')
& $pythonCommand.Source -B (Join-Path $root 'operations/remote/test-dre-validation-material.py')
& $pythonCommand.Source -B (Join-Path $root 'operations/remote/test-dre-restore-render.py')
& $pythonCommand.Source -B (Join-Path $root 'operations/remote/verify-blindou-data-artifacts.py') $root
& $pythonCommand.Source -B (Join-Path $root 'operations/remote/test-blindou-data-release-verify.py')
& $pythonCommand.Source -B (Join-Path $root 'operations/remote/test-blindou-data-secret-verify.py')
& $pythonCommand.Source -B (Join-Path $root 'operations/remote/test-blindou-data-ghcr-pull-verify.py')

$namespaceManifest = Get-Content -Raw -LiteralPath (Join-Path $root 'platform/base/namespaces.yaml')
if ($namespaceManifest.Contains('platform.servidor.local/deployment-gate: passed')) {
    throw 'O manifesto base nunca pode pré-aprovar o gate de contenção externa.'
}

$productionPolicy = Get-Content -Raw -LiteralPath (Join-Path $root 'platform/blindou/20-production-workload-policy.yaml')
if (-not $productionPolicy.Contains("namespaceObject.metadata.labels['platform.servidor.local/deployment-gate'] == 'passed'")) {
    throw 'A admissão de produção deve falhar fechada enquanto o gate não estiver passed.'
}

$edgePolicy = Get-Content -Raw -LiteralPath (Join-Path $root 'platform/security/blindou-edge-policy.yaml')
foreach ($invariant in @('ontDmzHostFeature: disabled', 'cloudflareConnectorOutsideEdgeNamespace: forbidden', 'portForwardingToServer: forbidden')) {
    if (-not $edgePolicy.Contains($invariant)) {
        throw "Invariante de contenção ausente: $invariant"
    }
}

Write-Host 'Repositório verificado: memória íntegra e nenhum arquivo sensível conhecido.'
