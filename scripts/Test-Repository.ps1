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
    'operations/Invoke-DreValidationExecutorBootstrap.ps1',
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
    'operations/remote/bootstrap-dre-validation-executor.sh',
    'operations/remote/verify-dre-validation-executor-artifacts.py',
    'platform/dre/controller-foundation.yaml',
    'platform/dre/edge-runtime.yaml',
    'platform/dre/validation-access.yaml',
    'platform/dre/monitoring/prometheus-alerts.yaml',
    'runbooks/dre-k3s.md',
    'runbooks/dre-validation-executor.md',
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
    'dre-controller-bootstrap-4902604dad96-20260902T184044Z',
    'afd4f686bd19df5d0fca20f8cfb26b092aef9a647f1e81e5ecf46eea78b26624',
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
    'a191f86039c1f7ccd8f04e2d0a6e2456a6c314d0',
    'dre-image-build-a191f86039c1-20260902T170613Z',
    'eb56421e194ddad8d8239907064aabd8b3132230bfb372ff92ee10e983908c63',
    'c93aa7638749f5aaac1a8e01787321889c78f0101809bb2880343478d0ba0467',
    '5a8b71e94f4607973145f02e27e01d50b9f7c7bc41e38d40b39606ad138b43b5',
    '0e69edd134a3c338baa1a6806920773615d682b18cbc6a0cba2a3b658ef9b63e',
    '$gh.Source auth token',
    'RedirectStandardInput = $true',
    'ConvertTo-WindowsProcessArgument',
    '$startInfo.Arguments =',
    '$sshProcess.StandardInput.NewLine = "`n"',
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
    'temporary_oci=',
    'digest OCI divergente',
    '--input "${temporary_oci}/${component}"',
    '--severity HIGH,CRITICAL',
    '--exit-code 1',
    '--skip-version-check',
    'exibindo no máximo 20',
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
    'a191f86039c1f7ccd8f04e2d0a6e2456a6c314d0',
    'dre-image-build-a191f86039c1-20260902T170613Z',
    '8cbdc0e22ad73ca7371ffd54b79607125046dc47ca9b49ea96f3a919caca68c7',
    '2975d0f651ad96ba8b80b9992ae1f9a964f4408569af5b6dc36544165c3926af',
    'ecf9961e3ec3a06b9b4521c234d8c838e02d9c1c8e41177a604fb1904656a30f',
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
    "sudo -S -p DRE_SUDO_PROMPT -- /bin/bash -c 'printf %s ",
    'Build remoto não retornou o atestado final esperado.',
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
    '--oci-worker-snapshotter=overlayfs',
    "grep -qw overlay /proc/filesystems",
    '--oci-worker-net=bridge',
    '--oci-cni-binary-dir',
    '--oci-max-parallelism=2',
    'maximum_buildkit_file_bytes = 96 * 1024 * 1024',
    'maximum_buildkit_total_bytes = 256 * 1024 * 1024',
    'rm -rf --one-file-system',
    'ghcr.io/gleisonsette/dre-validation-runner',
    'for attempt in 1 2 3 4 5',
    '[secondary-slotctl] ERRO: outra operação do slot está em andamento',
    'sleep "$attempt"'
)) {
    if (-not $dreImageBuildScript.Contains($invariant)) {
        throw "Build efêmero DRE perdeu a invariante: $invariant"
    }
}
$lockStart = $dreImageBuildScript.IndexOf(
    'exec 6>"$build_lock"',
    [StringComparison]::Ordinal
)
$unlockEnd = $dreImageBuildScript.IndexOf(
    'exec 6>&-',
    [StringComparison]::Ordinal
)
foreach ($controllerCheck in @(
    '/usr/local/sbin/dre-deployctl status',
    '/usr/local/sbin/blindou-deployctl status'
)) {
    $firstCheck = $dreImageBuildScript.IndexOf(
        $controllerCheck,
        [StringComparison]::Ordinal
    )
    $secondCheck = $dreImageBuildScript.IndexOf(
        $controllerCheck,
        $firstCheck + $controllerCheck.Length,
        [StringComparison]::Ordinal
    )
    if ($firstCheck -lt 0 -or $firstCheck -ge $lockStart -or
        $secondCheck -le $unlockEnd -or
        $dreImageBuildScript.LastIndexOf(
            $controllerCheck,
            [StringComparison]::Ordinal
        ) -ne $secondCheck) {
        throw "Verificação do build DRE pode executar sob lock próprio: $controllerCheck"
    }
}
$slotCheckToken = 'verify_secondary_slot \'
if ([regex]::Matches(
        $dreImageBuildScript,
        [regex]::Escape($slotCheckToken)
    ).Count -ne 2) {
    throw 'O build DRE deve verificar o slot antes e depois dos locks.'
}
$firstSlotCheck = $dreImageBuildScript.IndexOf(
    $slotCheckToken,
    [StringComparison]::Ordinal
)
$secondSlotCheck = $dreImageBuildScript.IndexOf(
    $slotCheckToken,
    $firstSlotCheck + $slotCheckToken.Length,
    [StringComparison]::Ordinal
)
if ($firstSlotCheck -lt 0 -or $firstSlotCheck -ge $lockStart -or
    $secondSlotCheck -le $unlockEnd) {
    throw 'A verificação classificada do slot não envolve corretamente os locks.'
}
if ([regex]::Matches(
        $dreImageBuildScript,
        'flock --timeout 30 [6-9]'
    ).Count -ne 4) {
    throw 'Locks do build DRE perderam o timeout limitado de 30 segundos.'
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
function Invoke-CheckedPython {
    param(
        [Parameter(Mandatory)][string]$Script,
        [string[]]$Arguments = @()
    )

    & $pythonCommand.Source -B $Script @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Verificação Python falhou: $Script (código $LASTEXITCODE)."
    }
}

Invoke-CheckedPython (Join-Path $root 'operations/remote/verify-saferwpp-foundation-artifacts.py')
Invoke-CheckedPython (Join-Path $root 'operations/remote/verify-dre-controller-artifacts.py')
Invoke-CheckedPython (Join-Path $root 'operations/remote/verify-dre-validation-executor-artifacts.py')
Invoke-CheckedPython (Join-Path $root 'operations/remote/test-dre-release-verify.py')
Invoke-CheckedPython (Join-Path $root 'operations/remote/test-dre-secret-material.py')
Invoke-CheckedPython (Join-Path $root 'operations/remote/test-dre-validation-material.py')
Invoke-CheckedPython (Join-Path $root 'operations/remote/test-dre-restore-render.py')
Invoke-CheckedPython `
    (Join-Path $root 'operations/remote/verify-blindou-data-artifacts.py') `
    @($root)
Invoke-CheckedPython (Join-Path $root 'operations/remote/test-blindou-data-release-verify.py')
Invoke-CheckedPython (Join-Path $root 'operations/remote/test-blindou-data-secret-verify.py')
Invoke-CheckedPython (Join-Path $root 'operations/remote/test-blindou-data-ghcr-pull-verify.py')

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
