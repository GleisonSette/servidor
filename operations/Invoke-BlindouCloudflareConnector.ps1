[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$server = "apiadmin@192.168.100.59"
$identity = Join-Path $env:LOCALAPPDATA "apiwpp\ssh\apiwpp_admin_ed25519"
$knownHosts = Join-Path $env:LOCALAPPDATA "apiwpp\ssh\known_hosts"
$remoteRoot = "/home/apiadmin/blindou-platform-bootstrap-cloudflare"
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
    @{ Local = "operations/remote/blindou-deployctl"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-deployctl.sudoers"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-release-verify.py"; Remote = "operations/remote/" },
    @{ Local = "operations/remote/blindou-ghcr-pull-verify.py"; Remote = "operations/remote/" },
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

Write-Host "Preparando o controlador fechado do conector Blindou." -ForegroundColor Cyan
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

Write-Host "Carregando a senha temporária somente em memória para o bootstrap fechado." -ForegroundColor Cyan
Invoke-BlindouSudoBootstrap `
    -ControllerSet DeployController `
    -SshArguments $sshArgs `
    -Server $server `
    -RemoteRoot $remoteRoot

Write-Host "No Chrome, clique em 'Copiar token' no Tunnel blindou-physical." -ForegroundColor Cyan
Write-Host "Depois cole abaixo. O conteúdo não aparecerá e não será salvo." -ForegroundColor Yellow
$secureInput = Read-Host "Token ou comando copiado" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
$rawInput = $null
$token = $null
try {
    $rawInput = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
    if ($rawInput -match '(?:--token|service\s+install)\s+["'']?([A-Za-z0-9._-]{80,4096})') {
        $token = $Matches[1]
    }
    elseif ($rawInput -match '^[A-Za-z0-9._-]{80,4096}$') {
        $token = $rawInput
    }
    else {
        throw "O conteúdo colado não contém um token de Tunnel reconhecível."
    }

    $safeSshArgs = @(
        "-F NUL",
        "-i `"$identity`"",
        "-o IdentitiesOnly=yes",
        "-o StrictHostKeyChecking=yes",
        "-o UserKnownHostsFile=`"$knownHosts`"",
        $server,
        "sudo -n /usr/local/sbin/blindou-deployctl provision-edge-connector blindou-edge-connector"
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
    if ($process.ExitCode -ne 0) { throw "Provisionamento do conector falhou." }
}
finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $token = $null
    $rawInput = $null
    $secureInput.Dispose()
}

& ssh.exe @sshArgs $server "sudo -n /usr/local/sbin/blindou-deployctl verify-edge-connector"
if ($LASTEXITCODE -ne 0) { throw "A verificação final do conector falhou." }
Write-Host "Conector Blindou instalado e verificado. Volte ao Codex." -ForegroundColor Green
Read-Host "Pressione ENTER para fechar"
