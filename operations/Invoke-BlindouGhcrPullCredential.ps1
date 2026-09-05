[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$server = "apiadmin@192.168.100.59"
$identity = Join-Path $env:LOCALAPPDATA "apiwpp\ssh\apiwpp_admin_ed25519"
$knownHosts = Join-Path $env:LOCALAPPDATA "apiwpp\ssh\known_hosts"
$remoteRoot = "/home/apiadmin/blindou-platform-bootstrap-ghcr"
$remoteArchive = "/home/apiadmin/blindou-platform-bootstrap-ghcr.tar.gz"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'Blindou.SudoBootstrap.psm1') -Force
$sshArgs = @(
    "-F", "NUL",
    "-i", $identity,
    "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=$knownHosts"
)

if (-not (Test-Path -LiteralPath $identity -PathType Leaf)) {
    throw "Chave SSH administrativa não encontrada."
}
if (-not (Test-Path -LiteralPath $knownHosts -PathType Leaf)) {
    throw "Arquivo known_hosts administrativo não encontrado."
}

$files = @(
    @{ Local = "operations/remote/blindou-hostctl"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-hostctl.sudoers"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-temporary-containment.service"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/bootstrap-blindou-hostctl.sh"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-deployctl"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-deployctl.sudoers"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-release-emergencyctl"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-release-verify.py"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-ghcr-pull-verify.py"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-pagarme-plans.py"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-dispatch-v3-jetstream.py"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-platform-metrics"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-platform-metrics.service"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-platform-metrics.timer"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-release-allowed-signers"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-backup-recipient.crt"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/bootstrap-blindou-deployctl.sh"; Remote = "operations/remote/" },
    @{ Local = "platform/blindou/00-namespaces.yaml"; Remote = "platform/blindou/" },
    @{ Local = "platform/blindou/10-quarantine.yaml"; Remote = "platform/blindou/" },
    @{ Local = "platform/blindou/15-edge-connector-gate.yaml"; Remote = "platform/blindou/" },
    @{ Local = "platform/blindou/16-edge-connector-runtime.yaml"; Remote = "platform/blindou/" },
    @{ Local = "platform/blindou/20-production-workload-policy.yaml"; Remote = "platform/blindou/" },
    @{ Local = "platform/base/service-exposure-policy.yaml"; Remote = "platform/base/" }
)

$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temporaryRoot = [IO.Path]::GetFullPath((
    Join-Path $temporaryBase ("blindou-ghcr-bootstrap-" + [guid]::NewGuid().ToString("N"))
))
if (-not $temporaryRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Diretório temporário escapou da raiz esperada."
}
$archivePath = Join-Path $temporaryRoot "bootstrap.tar.gz"

Write-Host "Preparando o cofre fechado da credencial GHCR somente leitura." -ForegroundColor Cyan
try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)
    foreach ($file in $files) {
        $localPath = Join-Path $repositoryRoot $file.Local
        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            throw "Artefato local ausente: $($file.Local)"
        }
    }
    $archiveFiles = @($files | ForEach-Object { $_.Local })
    & tar.exe -czf $archivePath -C $repositoryRoot @archiveFiles
    if ($LASTEXITCODE -ne 0) { throw "Falha ao empacotar os controladores." }

    & scp.exe @sshArgs $archivePath "${server}:$remoteArchive"
    if ($LASTEXITCODE -ne 0) { throw "Falha ao enviar o pacote único." }
    & ssh.exe @sshArgs $server (
        "install -d -m 0700 $remoteRoot && " +
        "tar --extract --gzip --file $remoteArchive --directory $remoteRoot && " +
        "chmod 0755 " +
        "$remoteRoot/operations/remote/bootstrap-blindou-hostctl.sh " +
        "$remoteRoot/operations/remote/bootstrap-blindou-deployctl.sh"
    )
    if ($LASTEXITCODE -ne 0) { throw "Falha ao extrair o pacote remoto." }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Host "Carregando a senha temporária somente em memória para os bootstraps fechados." -ForegroundColor Cyan
Invoke-BlindouSudoBootstrap `
    -ControllerSet HostAndDeployControllers `
    -SshArguments $sshArgs `
    -Server $server `
    -RemoteRoot $remoteRoot
& ssh.exe @sshArgs $server (
    "sudo -n /usr/local/sbin/blindou-hostctl verify && rm -f $remoteArchive"
)
if ($LASTEXITCODE -ne 0) { throw "Verificação posterior ao bootstrap falhou." }

Write-Host "Cole o PAT classic do GitHub com somente read:packages." -ForegroundColor Cyan
Write-Host "O conteúdo não aparecerá nem será salvo nesta máquina." -ForegroundColor Yellow
$secureInput = Read-Host "Credencial GHCR somente leitura" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
$token = $null
try {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
    if ($token -notmatch '^ghp_[A-Za-z0-9]{36,251}$') {
        throw "O conteúdo colado não possui o formato atual de PAT classic do GitHub."
    }

    $safeSshArgs = @(
        "-F NUL",
        "-i `"$identity`"",
        "-o IdentitiesOnly=yes",
        "-o StrictHostKeyChecking=yes",
        "-o UserKnownHostsFile=`"$knownHosts`"",
        $server,
        "sudo -n /usr/local/sbin/blindou-deployctl provision-ghcr-pull-credential blindou-ghcr-pull-credential"
    ) -join " "
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = "ssh.exe"
    $startInfo.Arguments = $safeSshArgs
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "Não foi possível iniciar o SSH seguro." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.NewLine = "`n"
    $process.StandardInput.WriteLine($token)
    $process.StandardInput.Close()
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($stdout) { Write-Host $stdout.TrimEnd() }
    if ($stderr) { Write-Host $stderr.TrimEnd() -ForegroundColor Red }
    if ($process.ExitCode -ne 0) { throw "Provisionamento seguro da credencial GHCR falhou." }
}
finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $token = $null
    $secureInput.Dispose()
}

& ssh.exe @sshArgs $server "sudo -n /usr/local/sbin/blindou-deployctl verify-ghcr-pull-credential"
if ($LASTEXITCODE -ne 0) { throw "A verificação final da credencial GHCR falhou." }
Write-Host "Credencial GHCR ativa, root-only e limitada a read:packages. O runtime permanece bloqueado." -ForegroundColor Green
Read-Host "Pressione ENTER para fechar"
