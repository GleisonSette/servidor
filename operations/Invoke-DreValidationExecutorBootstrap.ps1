[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Dre.SudoBootstrap.psm1') -Force

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$server = 'apiadmin@192.168.100.59'
$archivePaths = @(
    'operations/Dre.SudoBootstrap.psm1',
    'operations/Invoke-DreValidationExecutorBootstrap.ps1',
    'operations/remote/bootstrap-dre-validation-executor.sh',
    'operations/remote/verify-dre-validation-executor-artifacts.py',
    'runbooks/dre-validation-executor.md'
)

function Invoke-CheckedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage Código de saída: $LASTEXITCODE."
    }
}

function Wait-SshCadence {
    Start-Sleep -Seconds 15
}

Push-Location $repositoryRoot
try {
    $pathStatus = @(& git.exe status --porcelain=v1 -- @archivePaths)
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível conferir o estado Git do bootstrap do executor.'
    }
    if ($pathStatus.Count -ne 0) {
        throw 'Os artefatos do bootstrap do executor possuem alterações não commitadas.'
    }
    Invoke-CheckedProcess -FilePath 'python.exe' `
        -ArgumentList @(
            '-B',
            'operations/remote/verify-dre-validation-executor-artifacts.py'
        ) `
        -FailureMessage 'A verificação offline do executor DRE falhou.'

    $gitCommit = (& git.exe rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $gitCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Não foi possível determinar o commit aprovado.'
    }
    $originCommit = (& git.exe rev-parse origin/main).Trim()
    if ($LASTEXITCODE -ne 0 -or $originCommit -cne $gitCommit) {
        throw 'O bootstrap do executor exige HEAD já publicado em origin/main.'
    }
    $shortCommit = $gitCommit.Substring(0, 12)
    $timestamp = [DateTime]::UtcNow.ToString(
        'yyyyMMddTHHmmssZ',
        [Globalization.CultureInfo]::InvariantCulture
    )
    $localReleaseDirectory = Join-Path $env:LOCALAPPDATA `
        "SaferDock\dre\validation-executor\$gitCommit"
    New-Item -ItemType Directory -Path $localReleaseDirectory -Force | Out-Null
    $archive = Join-Path $localReleaseDirectory `
        "servidor-dre-validation-executor-$shortCommit.tar.gz"
    $temporaryArchive = "$archive.tmp"
    if (Test-Path -LiteralPath $temporaryArchive) {
        Remove-Item -LiteralPath $temporaryArchive -Force
    }
    Invoke-CheckedProcess -FilePath 'git.exe' `
        -ArgumentList (@(
            'archive',
            '--format=tar.gz',
            "--output=$temporaryArchive",
            $gitCommit,
            '--'
        ) + $archivePaths) `
        -FailureMessage 'Não foi possível criar o bundle fechado do executor DRE.'
    Move-Item -LiteralPath $temporaryArchive -Destination $archive -Force
    $expectedSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).
        Hash.ToLowerInvariant()

    $sshDirectory = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh'
    $identityFile = Join-Path $sshDirectory 'apiwpp_admin_ed25519'
    $knownHostsFile = Join-Path $sshDirectory 'known_hosts'
    foreach ($requiredFile in @($identityFile, $knownHostsFile)) {
        $item = Get-Item -LiteralPath $requiredFile -Force -ErrorAction Stop
        if ($item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'A identidade SSH ou known_hosts possui tipo inseguro.'
        }
    }
    $sshArguments = @(
        '-F', 'NUL',
        '-i', $identityFile,
        '-o', 'IdentitiesOnly=yes',
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=30',
        '-o', 'ServerAliveInterval=15',
        '-o', 'ServerAliveCountMax=8',
        '-o', 'PreferredAuthentications=publickey',
        '-o', 'PasswordAuthentication=no',
        '-o', 'KbdInteractiveAuthentication=no',
        '-o', 'KexAlgorithms=curve25519-sha256',
        '-o', 'HostKeyAlgorithms=ssh-ed25519',
        '-o', 'StrictHostKeyChecking=yes',
        '-o', "UserKnownHostsFile=$knownHostsFile"
    )
    $remoteRoot =
        "/home/apiadmin/dre-validation-executor-bootstrap-$shortCommit-$timestamp"
    $remoteArchive = "$remoteRoot/bundle.tar.gz"
    $remoteTemporaryArchive = "$remoteArchive.uploading"
    $remotePreflight = @'
set -eu
test "$(hostname)" = apiwpp
test "$(dpkg --print-architecture)" = amd64
. /etc/os-release
test "$ID" = ubuntu
test "$VERSION_ID" = 24.04
test ! -r /etc/rancher/k3s/k3s.yaml
if test -S /run/k3s/containerd/containerd.sock; then
  test ! -r /run/k3s/containerd/containerd.sock
fi
test ! -e /home/apiadmin/.local/share/containers/storage
sudo -n /usr/local/sbin/dre-deployctl status >/dev/null
sudo -n /usr/local/sbin/blindou-deployctl status >/dev/null
sudo -n /usr/local/sbin/secondary-slotctl verify >/dev/null
available_kib=$(df -Pk /tmp | awk 'NR==2 {print $4}')
test "$available_kib" -ge $((60 * 1024 * 1024))
printf 'dre_validation_executor_preflight=passed\n'
'@
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @($server, $remotePreflight)) `
        -FailureMessage 'O preflight do executor DRE falhou.'

    Wait-SshCadence
    $prepareStaging =
        "install -d -m 0700 '$remoteRoot' && " +
        "rm -f -- '$remoteTemporaryArchive'"
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @($server, $prepareStaging)) `
        -FailureMessage 'Não foi possível preparar o staging remoto.'

    Wait-SshCadence
    $scpArguments = $sshArguments + @(
        $archive,
        "${server}:$remoteTemporaryArchive"
    )
    Invoke-CheckedProcess -FilePath 'scp.exe' `
        -ArgumentList $scpArguments `
        -FailureMessage 'Não foi possível transportar o bundle do executor DRE.'

    Wait-SshCadence
    $finalizeStaging =
        "chmod 0600 '$remoteTemporaryArchive' && " +
        "mv -f -- '$remoteTemporaryArchive' '$remoteArchive' && " +
        "test `$(sha256sum '$remoteArchive' | cut -d' ' -f1) = '$expectedSha256'"
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @($server, $finalizeStaging)) `
        -FailureMessage 'O SHA-256 remoto do bundle do executor diverge.'

    Wait-SshCadence
    Invoke-DreValidationExecutorSudoBootstrap `
        -SshArguments $sshArguments `
        -Server $server `
        -RemoteRoot $remoteRoot `
        -ExpectedArchiveSha256 $expectedSha256 `
        -ExpectedGitCommit $gitCommit

    Wait-SshCadence
    $postInstall = @'
set -Eeuo pipefail
test ! -r /etc/rancher/k3s/k3s.yaml
if test -S /run/k3s/containerd/containerd.sock; then
  test ! -r /run/k3s/containerd/containerd.sock
fi
sudo -n /usr/local/sbin/dre-deployctl status >/dev/null
sudo -n /usr/local/sbin/blindou-deployctl status >/dev/null
sudo -n /usr/local/sbin/secondary-slotctl verify >/dev/null

workspace="$(mktemp -d /tmp/dre-validation-executor-smoke.XXXXXX)"
readonly workspace
cleanup() {
  result="$?"
  trap - EXIT
  if test -x /usr/bin/podman; then
    /usr/bin/podman --root "$workspace/storage" --runroot "$workspace/runroot" \
      --tmpdir "$workspace/tmp" --cgroup-manager=cgroupfs \
      --events-backend=file system reset --force >/dev/null 2>&1 || true
  fi
  rm -rf --one-file-system -- "$workspace"
  exit "$result"
}
trap cleanup EXIT
install -d -m 0700 "$workspace/storage" "$workspace/runroot" \
  "$workspace/tmp" "$workspace/config" "$workspace/cache"
export XDG_CONFIG_HOME="$workspace/config"
export XDG_CACHE_HOME="$workspace/cache"
podman_args=(
  --root "$workspace/storage"
  --runroot "$workspace/runroot"
  --tmpdir "$workspace/tmp"
  --cgroup-manager=cgroupfs
  --events-backend=file
)
/usr/bin/podman "${podman_args[@]}" info --format '{{.Host.Security.Rootless}}' |
  grep -Fx true
/usr/bin/podman "${podman_args[@]}" unshare awk \
  'NR==1 {if ($1 != 0 || $2 < 1 || $3 < 1) exit 1} END {if (NR < 2) exit 1}' \
  /proc/self/uid_map
cat >"$workspace/Containerfile" <<'EOF'
FROM docker.io/library/alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
RUN addgroup -g 4242 smoke && adduser -D -u 4242 -G smoke smoke
USER 4242:4242
ENTRYPOINT ["/bin/sh", "-ec"]
CMD ["test \"$(id -u)\" = 4242"]
EOF
/usr/bin/podman "${podman_args[@]}" build --pull=always \
  --file "$workspace/Containerfile" \
  --tag localhost/dre-validation-executor-smoke:verified "$workspace"
/usr/bin/podman "${podman_args[@]}" run --rm --init \
  localhost/dre-validation-executor-smoke:verified
cat >"$workspace/compose.yaml" <<'EOF'
services:
  smoke:
    image: localhost/dre-validation-executor-smoke:verified
    init: true
EOF
cat >"$workspace/bin-podman" <<EOF
#!/usr/bin/env bash
exec /usr/bin/podman --root '$workspace/storage' --runroot '$workspace/runroot' \\
  --tmpdir '$workspace/tmp' --cgroup-manager=cgroupfs --events-backend=file "\$@"
EOF
chmod 0700 "$workspace/bin-podman"
install -d -m 0700 "$workspace/bin"
mv "$workspace/bin-podman" "$workspace/bin/podman"
PATH="$workspace/bin:$PATH" podman-compose --file "$workspace/compose.yaml" config >/dev/null
/usr/bin/podman "${podman_args[@]}" system reset --force >/dev/null
test ! -S /run/podman/podman.sock
test ! -S "/run/user/$(id -u)/podman/podman.sock"
printf 'podman_version=%s\n' "$(podman --version | awk '{print $3}')"
printf 'podman_compose_version=%s\n' "$(podman-compose --version | awk '{print $NF}')"
printf 'dre_validation_executor_smoke=passed rootless=true daemon=false k3s_access=false\n'
'@
    Invoke-CheckedProcess -FilePath 'ssh.exe' `
        -ArgumentList ($sshArguments + @($server, $postInstall)) `
        -FailureMessage 'A prova rootless posterior à instalação falhou.'

    Write-Output (
        'dre_validation_executor_orchestration=passed ' +
        "commit=$gitCommit sha256=$expectedSha256 remote=$remoteArchive"
    )
}
finally {
    Pop-Location
}
