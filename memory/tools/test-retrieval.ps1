[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8 = [Text.UTF8Encoding]::new($false)
$OutputEncoding = $utf8
[Console]::OutputEncoding = $utf8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$memoryRoot = Split-Path -Parent $scriptDir
$casesPath = Join-Path $memoryRoot 'qa\casos.json'
$searchPath = Join-Path $scriptDir 'search-index.ps1'

if (-not (Test-Path -LiteralPath $casesPath -PathType Leaf)) {
    throw "Casos de QA ausentes: $casesPath"
}
if (-not (Test-Path -LiteralPath $searchPath -PathType Leaf)) {
    throw "Busca ausente: $searchPath"
}

$suite = Get-Content -Raw -Encoding UTF8 -LiteralPath $casesPath |
    ConvertFrom-Json
$failures = [Collections.Generic.List[string]]::new()
$passed = 0

foreach ($case in @($suite.cases)) {
    $results = @(& $searchPath -Query ([string]$case.query) -Top ([int]$case.top))
    $actual = @(
        $results |
            Where-Object { $_ -isnot [string] } |
            ForEach-Object { [string]$_.source_id } |
            Sort-Object -Unique
    )
    $expected = @($case.expected_source_ids | ForEach-Object { [string]$_ })
    $matches = @($expected | Where-Object { $_ -in $actual })
    if ($matches.Count -eq 0) {
        $failures.Add(("{0}: esperava uma de [{1}], recebeu [{2}]" -f
            $case.id, ($expected -join ', '), ($actual -join ', ')))
        Write-Output ("[FAIL] {0}" -f $case.id)
    }
    else {
        $passed++
        Write-Output ("[PASS] {0} -> {1}" -f
            $case.id, ($matches -join ', '))
    }
}

if ($failures.Count -gt 0) {
    throw ("QA de recuperacao falhou em {0}/{1} casos:`n{2}" -f
        $failures.Count, @($suite.cases).Count, ($failures -join "`n"))
}

Write-Output ("QA de recuperacao aprovado: {0}/{1} casos." -f
    $passed, @($suite.cases).Count)
