[CmdletBinding()]
param(
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ReleaseId = '1265c3be1e808d522887f38ff47e9a110533677a'
)

$ErrorActionPreference = 'Stop'
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$remoteRoot = '/home/apiadmin/blindou-platform-bootstrap-pull-proof'
$remoteArchive = '/home/apiadmin/blindou-platform-bootstrap-pull-proof.tar.gz'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
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
    & tar.exe -czf $archivePath -C $repositoryRoot @files
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao empacotar o controlador.' }

    & scp.exe @sshArgs $archivePath "${server}:$remoteArchive"
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao transferir o pacote.' }
    & ssh.exe @sshArgs $server (
        "install -d -m 0700 $remoteRoot && " +
        "tar --extract --gzip --file $remoteArchive --directory $remoteRoot && " +
        "chmod 0755 $remoteRoot/operations/remote/bootstrap-blindou-deployctl.sh"
    )
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar o inbox remoto.' }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Host 'Digite a senha de sudo uma vez para instalar o controlador versionado.' -ForegroundColor Yellow
Write-Host 'Depois, o servidor baixará e validará backend e redirector sem iniciar workloads.' -ForegroundColor Cyan
& ssh.exe -t @sshArgs $server (
    "cd $remoteRoot && " +
    'sudo ./operations/remote/bootstrap-blindou-deployctl.sh && ' +
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
Read-Host 'Pressione ENTER para fechar'
