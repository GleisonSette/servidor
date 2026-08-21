[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$server = "apiadmin@192.168.100.59"
$identity = Join-Path $env:LOCALAPPDATA "apiwpp\ssh\apiwpp_admin_ed25519"
$knownHosts = Join-Path $env:LOCALAPPDATA "apiwpp\ssh\known_hosts"
$remoteRoot = "/home/apiadmin/blindou-platform-bootstrap-ghcr"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
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
    @{ Local = "operations/remote/blindou-deployctl"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-deployctl.sudoers"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-release-verify.py"; Remote = "operations/remote/" },
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

Write-Host "Preparando o cofre fechado da credencial GHCR somente leitura." -ForegroundColor Cyan
& ssh.exe @sshArgs $server (
    "install -d -m 0700 " +
    "$remoteRoot/operations/remote $remoteRoot/platform/blindou $remoteRoot/platform/base"
)
if ($LASTEXITCODE -ne 0) { throw "Falha ao preparar o diretório remoto." }

foreach ($file in $files) {
    $localPath = Join-Path $repositoryRoot $file.Local
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        throw "Artefato local ausente: $($file.Local)"
    }
    & scp.exe @sshArgs $localPath "${server}:$remoteRoot/$($file.Remote)"
    if ($LASTEXITCODE -ne 0) { throw "Falha ao enviar $($file.Local)." }
}

Write-Host "Digite a senha de sudo para instalar o controlador atualizado." -ForegroundColor Yellow
& ssh.exe -t @sshArgs $server (
    "cd $remoteRoot && sudo ./operations/remote/bootstrap-blindou-deployctl.sh"
)
if ($LASTEXITCODE -ne 0) { throw "Bootstrap remoto falhou." }

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
