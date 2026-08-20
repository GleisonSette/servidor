[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Query,
    [ValidateRange(1, 20)][int]$Top = 6
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8 = [Text.UTF8Encoding]::new($false)
$OutputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$memoryRoot = Split-Path -Parent $scriptDir
$chunksPath = Join-Path $memoryRoot 'index\chunks.jsonl'
$bm25Path = Join-Path $memoryRoot 'index\bm25\index.json'

function Remove-Diacritics([string]$Value) {
    $normalized = $Value.Normalize([Text.NormalizationForm]::FormD)
    $builder = [Text.StringBuilder]::new()
    foreach ($character in $normalized.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne
            [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    $builder.ToString().Normalize([Text.NormalizationForm]::FormC)
}

$index = Get-Content -Raw -Encoding UTF8 -LiteralPath $bm25Path | ConvertFrom-Json
$chunks = @{}
Get-Content -Encoding UTF8 -LiteralPath $chunksPath | Where-Object { $_ } |
    ForEach-Object { $chunk=$_ | ConvertFrom-Json; $chunks[$chunk.chunk_id]=$chunk }
$queryTerms = @([Regex]::Matches((Remove-Diacritics $Query).ToLowerInvariant(),
    '(?:[a-z0-9][a-z0-9_-]{2,}|r2|ip|id|io|ha)') |
    ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($queryTerms.Count -eq 0) { throw 'A consulta nao possui termos indexaveis.' }

$documentCount = @($index.documents).Count
$results = [Collections.Generic.List[object]]::new()
foreach ($document in $index.documents) {
    $score = 0.0
    $matched = [Collections.Generic.List[string]]::new()
    foreach ($term in $queryTerms) {
        $dfp = $index.document_frequencies.PSObject.Properties[$term]
        $tfp = $document.term_frequencies.PSObject.Properties[$term]
        if ($null -eq $dfp -or $null -eq $tfp) { continue }
        $df=[double]$dfp.Value; $tf=[double]$tfp.Value
        $idf=[Math]::Log(1+(($documentCount-$df+0.5)/($df+0.5)))
        $normalizer=$tf+[double]$index.k1*(1-[double]$index.b+
            [double]$index.b*([double]$document.length/[double]$index.average_document_length))
        $score += $idf*(($tf*([double]$index.k1+1))/$normalizer)
        $matched.Add($term)
    }
    if ($score -le 0) { continue }
    $chunk=$chunks[[string]$document.chunk_id]
    $preview=([string]$chunk.text -replace '\s+',' ').Trim()
    if ($preview.Length -gt 220) { $preview=$preview.Substring(0,217)+'...' }
    $results.Add([pscustomobject][ordered]@{
        score=[Math]::Round($score,4); source_id=$chunk.source_id
        source_path=$chunk.source_path
        section=$chunk.section; matched_terms=@($matched); preview=$preview
    })
}
$ranked=@($results | Sort-Object @{Expression='score';Descending=$true},source_path |
    Select-Object -First $Top)
if ($ranked.Count -eq 0) { Write-Output 'Nenhum chunk encontrado.'; exit 0 }
$ranked
