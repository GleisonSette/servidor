Set-StrictMode -Version Latest

function Read-BlindouSudoPassword {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvFile
    )

    $fullPath = [IO.Path]::GetFullPath($EnvFile)
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'O arquivo temporário de senha deve ser regular e não simbólico.'
    }
    if ($item.Length -gt 65536) {
        throw 'O arquivo temporário de senha excede o limite de 64 KiB.'
    }

    $password = $null
    $matchCount = 0
    $lines = [IO.File]::ReadLines($fullPath).GetEnumerator()
    try {
        while ($lines.MoveNext()) {
            $line = [string]$lines.Current
            if ($line.StartsWith('KEY_SERVIDOR=', [StringComparison]::Ordinal)) {
                $matchCount++
                $password = $line.Substring('KEY_SERVIDOR='.Length)
            }
        }
    }
    finally {
        $lines.Dispose()
    }

    if ($matchCount -ne 1) {
        throw 'O arquivo temporário deve conter exatamente uma chave KEY_SERVIDOR.'
    }
    if ([string]::IsNullOrEmpty($password) -or $password.Length -gt 1024 -or
        $password.IndexOf([char]0) -ge 0 -or
        $password.Contains("`r") -or $password.Contains("`n")) {
        throw 'KEY_SERVIDOR está vazia ou possui formato inválido.'
    }

    return $password
}

function Invoke-BlindouSudoBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('DeployController', 'HostAndDeployControllers')]
        [string]$ControllerSet,

        [Parameter(Mandatory = $true)]
        [string[]]$SshArguments,

        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$RemoteRoot
    )

    if ($Server -cne 'apiadmin@192.168.100.59') {
        throw 'O bootstrap automatizado aceita somente o servidor físico aprovado.'
    }
    if ($RemoteRoot -notmatch '^/home/apiadmin/blindou-platform-bootstrap(?:-[a-z0-9-]+)?(?:/[0-9a-f]{40})?$') {
        throw 'Diretório remoto fora do staging fechado do Blindou.'
    }
    foreach ($requiredOption in @('IdentitiesOnly=yes', 'StrictHostKeyChecking=yes')) {
        if ($SshArguments -notcontains $requiredOption) {
            throw "Opção SSH obrigatória ausente: $requiredOption"
        }
    }

    $remoteCommand = switch ($ControllerSet) {
        'DeployController' {
            "cd $RemoteRoot && sudo -S -p '' -- ./operations/remote/bootstrap-blindou-deployctl.sh"
        }
        'HostAndDeployControllers' {
            "cd $RemoteRoot && " +
            "sudo -S -p '' -- ./operations/remote/bootstrap-blindou-hostctl.sh && " +
            "sudo -S -p '' -- ./operations/remote/bootstrap-blindou-deployctl.sh"
        }
    }

    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $envFile = Join-Path $repositoryRoot '.env'
    $password = Read-BlindouSudoPassword -EnvFile $envFile
    try {
        $password | & ssh.exe @SshArguments $Server $remoteCommand
        if ($LASTEXITCODE -ne 0) {
            throw 'Bootstrap remoto autenticado falhou.'
        }
    }
    finally {
        $password = $null
    }
}

Export-ModuleMember -Function Invoke-BlindouSudoBootstrap
