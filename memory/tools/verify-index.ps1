[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$memoryRoot = Split-Path -Parent $scriptDir
$repoRoot = [IO.Path]::GetFullPath((Join-Path $memoryRoot '..'))
$catalog = Get-Content -Raw -Encoding UTF8 -LiteralPath (
    Join-Path $memoryRoot 'metadata\sources.json') | ConvertFrom-Json
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (
    Join-Path $memoryRoot 'metadata\corpus_manifest.json') | ConvertFrom-Json
$bm25 = Get-Content -Raw -Encoding UTF8 -LiteralPath (
    Join-Path $memoryRoot 'index\bm25\index.json') | ConvertFrom-Json
$chunks = @(Get-Content -Encoding UTF8 -LiteralPath (
    Join-Path $memoryRoot 'index\chunks.jsonl') | Where-Object { $_ } |
    ForEach-Object { $_ | ConvertFrom-Json })
if ($chunks.Count -eq 0) { throw 'O indice nao possui chunks.' }

$sourceIds=@{}
foreach ($source in $catalog.sources) {
    if ($sourceIds.ContainsKey([string]$source.source_id)) {
        throw "source_id duplicado: $($source.source_id)"
    }
    $sourceIds[[string]$source.source_id]=$true
    $absolute=[IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$source.canon_path)))
    if (-not $absolute.StartsWith($repoRoot.TrimEnd('\')+'\',
        [StringComparison]::OrdinalIgnoreCase)) { throw 'Fonte fora do repositorio.' }
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
        throw "Fonte ausente: $($source.canon_path)"
    }
    $text=Get-Content -Raw -Encoding UTF8 -LiteralPath $absolute
    foreach ($field in @('canon_id:','source_path:','generated_from:','updated_at:','status:')) {
        if (-not $text.Contains($field)) { throw "$field ausente em $absolute" }
    }
    if (-not $text.Contains("source_path: $($source.canon_path)")) {
        throw "source_path divergente em $absolute"
    }
}

$chunkIds=@{}
foreach ($chunk in $chunks) {
    if ($chunkIds.ContainsKey([string]$chunk.chunk_id)) {
        throw "chunk duplicado: $($chunk.chunk_id)"
    }
    if (-not $sourceIds.ContainsKey([string]$chunk.source_id)) {
        throw "chunk sem fonte: $($chunk.chunk_id)"
    }
    if ([int]$chunk.token_count_estimate -le 0) { throw 'Estimativa invalida.' }
    $chunkIds[[string]$chunk.chunk_id]=$true
}
$bm25Ids=@{}
foreach ($document in $bm25.documents) {
    if (-not $chunkIds.ContainsKey([string]$document.chunk_id)) {
        throw "BM25 sem chunk: $($document.chunk_id)"
    }
    if ([int]$document.length -le 0) { throw 'Documento BM25 vazio.' }
    $bm25Ids[[string]$document.chunk_id]=$true
}
foreach ($id in $chunkIds.Keys) {
    if (-not $bm25Ids.ContainsKey($id)) { throw "Chunk fora do BM25: $id" }
}
if ([int]$manifest.layers.canon -ne @($catalog.sources).Count -or
    [int]$manifest.layers.index_chunks -ne $chunks.Count) {
    throw 'Manifesto e indice divergem.'
}
if ([string]$bm25.algorithm -ne 'BM25' -or
    [double]$bm25.average_document_length -le 0) { throw 'BM25 invalido.' }

$required=@('indice-canonico','estado-atual','arquitetura-plataforma',
    'plano-implementacao','historico-execucao','decisoes')
foreach ($id in $required) {
    if (-not $sourceIds.ContainsKey($id)) { throw "Fonte obrigatoria ausente: $id" }
    if (-not ($chunks | Where-Object source_id -eq $id)) { throw "Fonte sem chunks: $id" }
}
$agents=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot 'AGENTS.md')
foreach ($entry in @('memory/canon/index.md',
    'memory/metadata/politica-composicao-contexto.md','memory/tools/search-index.ps1')) {
    if (-not $agents.Contains($entry)) { throw "AGENTS.md nao referencia $entry" }
}
Write-Output ("Memoria RAG verificada: {0} chunks e {1} fontes." -f
    $chunks.Count,$sourceIds.Count)
