[CmdletBinding()]
param(
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ReleaseId = '1265c3be1e808d522887f38ff47e9a110533677a',

    [Parameter(Mandatory = $true)]
    [string]$BundleDirectory
)

$ErrorActionPreference = 'Stop'
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$remoteRoot = "/home/apiadmin/blindou-platform-bootstrap-pull-proof/$ReleaseId"
$remoteArchive = "/home/apiadmin/blindou-platform-bootstrap-pull-proof-$ReleaseId.tar.gz"
$remoteInbox = "/home/apiadmin/blindou-deploy-inbox/$ReleaseId"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'Blindou.SudoBootstrap.psm1') -Force
$sshArgs = @(
    '-F', 'NUL',
    '-i', $identity,
    '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$knownHosts"
)

foreach ($required in @($identity, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Arquivo administrativo ausente: $required"
    }
}

$files = @(
    'operations/remote/blindou-deployctl',
    'operations/remote/blindou-release-emergencyctl',
    'operations/remote/blindou-deployctl.sudoers',
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
$bundleFiles = @(
    'release.manifest',
    'release.manifest.sig',
    'rendered.tar.gz'
)
$bundleRoot = [IO.Path]::GetFullPath($BundleDirectory)
$bundleRootItem = Get-Item -LiteralPath $bundleRoot -ErrorAction Stop
if (-not $bundleRootItem.PSIsContainer -or
    ($bundleRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'BundleDirectory deve ser um diretório regular, não simbólico.'
}
foreach ($file in $bundleFiles) {
    $item = Get-Item -LiteralPath (Join-Path $bundleRoot $file) -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Artefato de release inválido: $file"
    }
}
$manifest = Get-Content -LiteralPath (Join-Path $bundleRoot 'release.manifest')
foreach ($requiredLine in @(
    'schema=1',
    'project=blindou',
    "release_id=$ReleaseId",
    "revision=$ReleaseId",
    'source_state=clean'
)) {
    if ($manifest -notcontains $requiredLine) {
        throw "Manifesto da release não contém: $requiredLine"
    }
}
if (($manifest | Where-Object { $_ -match '^bundle_sha256=[0-9a-f]{64}$' }).Count -ne 1) {
    throw 'Manifesto da release não contém um único bundle_sha256 válido.'
}

$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temporaryRoot = [IO.Path]::GetFullPath((
    Join-Path $temporaryBase ('blindou-ghcr-pull-proof-' + [guid]::NewGuid().ToString('N'))
))
if (-not $temporaryRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Diretório temporário escapou da raiz esperada.'
}
$archivePath = Join-Path $temporaryRoot 'bootstrap.tar.gz'

Write-Host 'Preparando a prova fechada de download das imagens privadas.' -ForegroundColor Cyan
try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)
    foreach ($file in $files) {
        $localPath = Join-Path $repositoryRoot $file
        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            throw "Artefato local ausente: $file"
        }
    }
    & tar.exe -czf $archivePath -C $repositoryRoot @files -C $bundleRoot @bundleFiles
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao empacotar o controlador.' }

    & scp.exe @sshArgs $archivePath "${server}:$remoteArchive"
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao transferir o pacote.' }
    & ssh.exe @sshArgs $server (
        "install -d -m 0700 $remoteRoot && " +
        "tar --extract --gzip --file $remoteArchive --directory $remoteRoot && " +
        "chmod 0755 $remoteRoot/operations/remote/bootstrap-blindou-deployctl.sh && " +
        "install -d -m 0700 $remoteInbox && " +
        "install -m 0600 $remoteRoot/release.manifest $remoteInbox/release.manifest && " +
        "install -m 0600 $remoteRoot/release.manifest.sig $remoteInbox/release.manifest.sig && " +
        "install -m 0600 $remoteRoot/rendered.tar.gz $remoteInbox/rendered.tar.gz"
    )
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar o inbox remoto.' }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Host 'Carregando a senha temporária somente em memória para o bootstrap fechado.' -ForegroundColor Cyan
Invoke-BlindouSudoBootstrap `
    -ControllerSet DeployController `
    -SshArguments $sshArgs `
    -Server $server `
    -RemoteRoot $remoteRoot

Write-Host 'Validando a release e as quatro imagens privadas sem iniciar workloads.' -ForegroundColor Cyan
& ssh.exe @sshArgs $server (
    "sudo -n /usr/local/sbin/blindou-deployctl validate-release $ReleaseId && " +
    "sudo -n /usr/local/sbin/blindou-deployctl verify-ghcr-candidate-pull $ReleaseId && " +
    'sudo -n /usr/local/sbin/blindou-deployctl status && ' +
    'sudo -n /usr/local/sbin/blindou-hostctl verify && ' +
    'sudo -n /usr/local/sbin/apiwpp-deployctl verify && ' +
    "rm -f $remoteArchive"
)
if ($LASTEXITCODE -ne 0) {
    throw 'Instalação ou prova de pull falhou; nenhum workload foi autorizado.'
}

Write-Host 'Prova concluída. Volte ao Codex.' -ForegroundColor Green
