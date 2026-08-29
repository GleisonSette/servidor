[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ReleaseId,

    [Parameter(Mandatory = $true)]
    [string]$BundleDirectory,

    [Parameter(Mandatory = $true)]
    [ValidateSet('PROVAR PULL POSTGRESQL')]
    [string]$Confirmation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$bundleRoot = [IO.Path]::GetFullPath($BundleDirectory)
$bundleFiles = @(
    'blindou-data.tar.gz',
    'data-release.manifest',
    'data-release.manifest.sig'
)

function Invoke-CheckedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage Código de saída: $LASTEXITCODE."
    }
}

$bundleItem = Get-Item -LiteralPath $bundleRoot -Force -ErrorAction Stop
if (-not $bundleItem.PSIsContainer -or
    ($bundleItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'BundleDirectory precisa ser um diretório regular.'
}
$actualFiles = @(Get-ChildItem -LiteralPath $bundleRoot -Force | ForEach-Object Name | Sort-Object)
if (Compare-Object -ReferenceObject ($bundleFiles | Sort-Object) -DifferenceObject $actualFiles) {
    throw 'BundleDirectory não contém exatamente os três artefatos autorizados.'
}
foreach ($file in $bundleFiles) {
    $item = Get-Item -LiteralPath (Join-Path $bundleRoot $file) -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Artefato de bundle inválido: $file"
    }
}
$manifest = Get-Content -LiteralPath (Join-Path $bundleRoot 'data-release.manifest')
foreach ($requiredLine in @(
    'schema=1',
    'project=blindou',
    "release_id=$ReleaseId",
    "revision=$ReleaseId",
    'source_state=clean',
    'cutover_authorized=false'
)) {
    if ($manifest -notcontains $requiredLine) {
        throw "Manifesto de dados não contém: $requiredLine"
    }
}
if (($manifest | Where-Object {
            $_ -cmatch '^image=ghcr\.io/gleisonsette/blindou-postgres@sha256:[0-9a-f]{64}$'
        }).Count -ne 1) {
    throw 'Manifesto não contém exatamente uma imagem PostgreSQL privada por digest.'
}

foreach ($required in @($identity, $knownHosts)) {
    $item = Get-Item -LiteralPath $required -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'A identidade SSH ou known_hosts possui tipo inseguro.'
    }
}
$sshArgs = @(
    '-F', 'NUL',
    '-i', $identity,
    '-o', 'IdentitiesOnly=yes',
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=15',
    '-o', 'KexAlgorithms=curve25519-sha256',
    '-o', 'HostKeyAlgorithms=ssh-ed25519',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$knownHosts"
)

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) `
    ('blindou-data-pull-' + [guid]::NewGuid().ToString('N'))
$archive = Join-Path $temporaryRoot 'bundle.tar.gz'
$remoteArchive = "/home/apiadmin/blindou-data-inbox-$ReleaseId.tar.gz"
$remoteInbox = "/home/apiadmin/blindou-data-inbox/$ReleaseId"

try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)
    Invoke-CheckedProcess -FilePath 'tar.exe' `
        -ArgumentList (@('-czf', $archive, '-C', $bundleRoot) + $bundleFiles) `
        -FailureMessage 'Não foi possível empacotar o bundle de dados.'
    $archiveSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
    Invoke-CheckedProcess -FilePath 'scp.exe' `
        -ArgumentList ($sshArgs + @($archive, "${server}:$remoteArchive.uploading")) `
        -FailureMessage 'Não foi possível transportar o bundle de dados.'
    $prepare = @"
set -eu
test "`$(hostname)" = apiwpp
test "`$(sha256sum '$remoteArchive.uploading' | cut -d' ' -f1)" = '$archiveSha256'
mv -f -- '$remoteArchive.uploading' '$remoteArchive'
install -d -m 0700 '$remoteInbox'
tar --extract --gzip --file '$remoteArchive' --directory '$remoteInbox'
chmod 0600 '$remoteInbox/blindou-data.tar.gz' '$remoteInbox/data-release.manifest' '$remoteInbox/data-release.manifest.sig'
"@
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArgs + @($server, $prepare)) `
        -FailureMessage 'O inbox remoto do bundle divergiu.'

    $proof = @"
set -eu
sudo -n /usr/local/sbin/blindou-datactl validate-release '$ReleaseId'
sudo -n /usr/local/sbin/blindou-datactl pull-proof '$ReleaseId' blindou-data-pull-proof
sudo -n /usr/local/sbin/blindou-datactl verify-quarantine
sudo -n /usr/local/sbin/blindou-datactl status
sudo -n /usr/local/sbin/blindou-hostctl verify
sudo -n /usr/local/sbin/apiwpp-deployctl verify
"@
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArgs + @($server, $proof)) `
        -FailureMessage 'A prova viva direta do PostgreSQL falhou.'
    Write-Output "blindou_data_pull_proof=passed release=$ReleaseId archive_sha256=$archiveSha256"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
