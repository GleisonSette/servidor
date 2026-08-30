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
    'operations/Dre.ImageBuild.psm1',
    'operations/Invoke-DreImageBuild.ps1',
    'operations/Invoke-DreImagePublish.ps1',
    'operations/remote/build-dre-images.sh',
    'operations/remote/publish-dre-images.sh',
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
    'dre-controller-bootstrap-4902604dad96-20260830T223903Z',
    '3be819ac84ec9a49dab1230127ad921fb4e09ebb678174621faddd6d4e8d0065',
    '4902604dad96d9b07f4010308d30e3815cb4e76446855d925079be0e3b922ce9',
    'StrictHostKeyChecking=yes'
)) {
    if (-not $dreBootstrap.Contains($invariant)) {
        throw "Orquestrador DRE diverge do bundle aprovado: $invariant"
    }
}
$dreImagePublish = Get-Content -Raw -LiteralPath (
    Join-Path $root 'operations/Invoke-DreImagePublish.ps1'
)
foreach ($invariant in @(
    '92776fcbf215e5bdd32e86f80530714983f84f4d96be91fc5bde51c391523d7a',
    'c93aa7638749f5aaac1a8e01787321889c78f0101809bb2880343478d0ba0467',
    '2a2e837a2c8d59ec9af5472ee22d3b04ee463c4e44476ecf993fd1e5ab6ebc7f',
    'bbb64b9695866ce4a7a8f5c9592002c5961cab378577fa3f8a040df362b9b2ea',
    '$gh.Source auth token',
    'StrictHostKeyChecking=yes'
)) {
    if (-not $dreImagePublish.Contains($invariant)) {
        throw "Orquestrador da publicação DRE diverge: $invariant"
    }
}
$dreImagePublishScript = Get-Content -Raw -LiteralPath (
    Join-Path $root 'operations/remote/publish-dre-images.sh'
)
foreach ($invariant in @(
    'oci-archive:',
    '--severity HIGH,CRITICAL',
    '--exit-code 1',
    'registry login ghcr.io',
    '--pass-stdin',
    'ghcr.io/gleisonsette/dre-validation-runner'
)) {
    if (-not $dreImagePublishScript.Contains($invariant)) {
        throw "Publicação DRE perdeu a invariante: $invariant"
    }
}

$dreImageBuild = Get-Content -Raw -LiteralPath (
    Join-Path $root 'operations/Invoke-DreImageBuild.ps1'
)
foreach ($invariant in @(
    '25dc4f8996699a5c9870294666391eb8bbab7c3e',
    'dre-image-build-25dc4f899669-20260830T221500Z',
    'a5303a241928ea78223bf7cddfb5425fc77d14acbc96c9c249dcca586ad70099',
    '2975d0f651ad96ba8b80b9992ae1f9a964f4408569af5b6dc36544165c3926af',
    'ef848fc154dc9cc39256db43fdba5049c8cd7f19d5aa3d4a5261bc7b1e58705d',
    'StrictHostKeyChecking=yes'
)) {
    if (-not $dreImageBuild.Contains($invariant)) {
        throw "Orquestrador do build DRE diverge do artefato aprovado: $invariant"
    }
}
$dreImageBuildModule = Get-Content -Raw -LiteralPath (
    Join-Path $root 'operations/Dre.ImageBuild.psm1'
)
foreach ($invariant in @(
    'KEY_SERVIDOR=',
    'sudo -S -p',
    'Read-DreImageBuildSudoPassword',
    'New-DreImageBuildRootWrapper'
)) {
    if (-not $dreImageBuildModule.Contains($invariant)) {
        throw "Helper sudo do build DRE perdeu a invariante: $invariant"
    }
}
$dreImageBuildScript = Get-Content -Raw -LiteralPath (
    Join-Path $root 'operations/remote/build-dre-images.sh'
)
foreach ($invariant in @(
    '--containerd-worker=false',
    '--oci-worker-snapshotter=native',
    '--oci-worker-net=bridge',
    '--oci-max-parallelism=2',
    'rm -rf --one-file-system',
    'ghcr.io/gleisonsette/dre-validation-runner'
)) {
    if (-not $dreImageBuildScript.Contains($invariant)) {
        throw "Build efêmero DRE perdeu a invariante: $invariant"
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
