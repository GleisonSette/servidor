[CmdletBinding()]
param(
    [string]$GeneratedAt = (Get-Date -Format 'yyyy-MM-dd'),
    [ValidateRange(1000, 12000)]
    [int]$MaxChunkChars = 3200
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$utf8 = [Text.UTF8Encoding]::new($false)
$OutputEncoding = $utf8
[Console]::OutputEncoding = $utf8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$memoryRoot = Split-Path -Parent $scriptDir
$repoRoot = [IO.Path]::GetFullPath((Join-Path $memoryRoot '..'))
$sourcesPath = Join-Path $memoryRoot 'metadata\sources.json'
$chunksPath = Join-Path $memoryRoot 'index\chunks.jsonl'
$bm25Path = Join-Path $memoryRoot 'index\bm25\index.json'
$manifestPath = Join-Path $memoryRoot 'metadata\corpus_manifest.json'

function Write-Utf8Lf([string]$Path, [string]$Content) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, ($Content -replace "`r`n", "`n"), $utf8)
}

function Resolve-RepoPath([string]$RelativePath) {
    $absolute = [IO.Path]::GetFullPath((Join-Path $repoRoot $RelativePath))
    $prefix = $repoRoot.TrimEnd('\') + '\'
    if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Fonte fora do repositorio: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
        throw "Fonte inexistente: $RelativePath"
    }
    $absolute
}

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

function Get-MarkdownSections([string]$Path) {
    $sections = [Collections.Generic.List[object]]::new()
    $title = ''
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^#{2,3}\s+(.+?)\s*$') {
            if ($title -and $lines.Count -gt 0) {
                $body = ($lines -join "`n").Trim()
                if ($body) { $sections.Add([pscustomobject]@{ Title=$title; Body=$body }) }
            }
            $title = $Matches[1].Trim()
            $lines.Clear()
        } elseif ($title) {
            $lines.Add($line)
        }
    }
    if ($title -and $lines.Count -gt 0) {
        $body = ($lines -join "`n").Trim()
        if ($body) { $sections.Add([pscustomobject]@{ Title=$title; Body=$body }) }
    }
    $sections
}

function Split-Section([string]$Text, [int]$Limit) {
    $parts = [Collections.Generic.List[string]]::new()
    $current = ''
    foreach ($paragraph in [Regex]::Split($Text.Trim(), '(?:\r?\n){2,}')) {
        $candidate = if ($current) { "$current`n`n$paragraph" } else { $paragraph }
        if ($candidate.Length -le $Limit) { $current = $candidate; continue }
        if ($current) { $parts.Add($current.Trim()); $current = '' }
        if ($paragraph.Length -le $Limit) { $current = $paragraph; continue }
        for ($offset=0; $offset -lt $paragraph.Length; $offset += $Limit) {
            $length = [Math]::Min($Limit, $paragraph.Length - $offset)
            $parts.Add($paragraph.Substring($offset, $length).Trim())
        }
    }
    if ($current) { $parts.Add($current.Trim()) }
    $parts
}

$stopWords = @('a','ao','aos','as','com','como','da','das','de','do','dos','e','em',
    'entre','essa','esse','esta','este','foi','mais','mas','na','nas','nao','no',
    'nos','o','os','ou','para','pela','pelo','por','que','se','sem','ser','sua',
    'suas','um','uma','usar','quando','onde','deve','devem','pode','podem','atual')
$stopSet = @{}
foreach ($word in $stopWords) { $stopSet[$word] = $true }
$tokenPattern = '(?:[a-z0-9][a-z0-9_-]{2,}|r2|ip|id|io|ha)'

function Get-Tokens([string]$Text) {
    $tokens = [Collections.Generic.List[string]]::new()
    $folded = (Remove-Diacritics $Text).ToLowerInvariant()
    foreach ($match in [Regex]::Matches($folded, $tokenPattern)) {
        if (-not $stopSet.ContainsKey($match.Value)) { $tokens.Add($match.Value) }
    }
    $tokens
}

$catalog = Get-Content -Raw -Encoding UTF8 -LiteralPath $sourcesPath | ConvertFrom-Json
$chunks = [Collections.Generic.List[object]]::new()
$documents = [Collections.Generic.List[object]]::new()

foreach ($source in $catalog.sources) {
    $absolute = Resolve-RepoPath ([string]$source.canon_path)
    $sequence = 0
    foreach ($section in Get-MarkdownSections $absolute) {
        if ((Remove-Diacritics $section.Title).ToLowerInvariant() -eq 'metadata') { continue }
        foreach ($part in Split-Section $section.Body $MaxChunkChars) {
            $sequence++
            $chunkId = '{0}-canon-{1:000}' -f $source.source_id, $sequence
            $tags = @($source.tags | Select-Object -Unique)
            $chunk = [ordered]@{
                chunk_id = $chunkId
                source_id = [string]$source.source_id
                source_path = [string]$source.canon_path
                section = [string]$section.Title
                tags = $tags
                text = [string]$part
                token_count_estimate = [int][Math]::Ceiling($part.Length / 4.0)
            }
            $chunks.Add([pscustomobject]$chunk)
            $frequencies = [ordered]@{}
            $tokens = @(Get-Tokens ((@($tags) -join ' ') + "`n" + $section.Title + "`n" + $part))
            foreach ($token in $tokens) {
                if ($frequencies.Contains($token)) { $frequencies[$token]++ }
                else { $frequencies[$token] = 1 }
            }
            $documents.Add([pscustomobject][ordered]@{
                chunk_id = $chunkId
                length = $tokens.Count
                term_frequencies = $frequencies
            })
        }
    }
}

Write-Utf8Lf $chunksPath ((@($chunks | ForEach-Object {
    $_ | ConvertTo-Json -Depth 8 -Compress
}) -join "`n") + "`n")

$documentFrequencies = [ordered]@{}
foreach ($document in $documents) {
    foreach ($term in $document.term_frequencies.Keys) {
        if ($documentFrequencies.Contains($term)) { $documentFrequencies[$term]++ }
        else { $documentFrequencies[$term] = 1 }
    }
}
$averageLength = [Math]::Round((($documents | Measure-Object length -Average).Average), 4)
$bm25 = [ordered]@{
    version = '0.1.0'
    generated_at = $GeneratedAt
    algorithm = 'BM25'
    k1 = 1.2
    b = 0.75
    average_document_length = $averageLength
    document_frequencies = $documentFrequencies
    description = 'Indice BM25 auditavel da plataforma local compartilhada.'
    documents = $documents.ToArray()
}
Write-Utf8Lf $bm25Path (($bm25 | ConvertTo-Json -Depth 8) + "`n")

$manifest = [ordered]@{
    manifest_version = '0.1.0'
    generated_at = $GeneratedAt
    project = 'servidor-local-compartilhado'
    memory_root = 'memory'
    source_scope = 'Host, K3s, apiwpp existente, Blindou, operacao, seguranca e continuidade.'
    layers = [ordered]@{ canon=@($catalog.sources).Count; index_chunks=$chunks.Count }
    topics = @($catalog.sources | ForEach-Object { $_.source_id })
    codex_entrypoints = @('AGENTS.md','memory/canon/index.md',
        'memory/metadata/politica-composicao-contexto.md')
}
Write-Utf8Lf $manifestPath (($manifest | ConvertTo-Json -Depth 8) + "`n")
Write-Output ("Indice RAG reconstruido: {0} chunks em {1} canons." -f
    $chunks.Count, @($catalog.sources).Count)
