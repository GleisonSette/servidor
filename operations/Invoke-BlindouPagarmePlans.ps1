[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$ConfirmCreation,
    [string]$ReceiptPath = (Join-Path $env:LOCALAPPDATA 'blindou\pagarme\plans-receipt.json')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$apiBaseUri = 'https://api.pagar.me/core/v5'
$catalogVersion = '0005'
$server = 'apiadmin@192.168.100.59'
$identity = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\apiwpp_admin_ed25519'
$knownHosts = Join-Path $env:LOCALAPPDATA 'apiwpp\ssh\known_hosts'
$utf8Encoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding
$catalog = @(
    [pscustomobject]@{
        Code = 'iniciante'
        Name = 'Iniciante'
        Description = 'Para quem está começando a montar sua operação'
        PriceCents = 29700
    },
    [pscustomobject]@{
        Code = 'operador_junior'
        Name = 'Operador Júnior'
        Description = 'Para quem já colocou a operação para rodar'
        PriceCents = 49700
    },
    [pscustomobject]@{
        Code = 'operador_pleno'
        Name = 'Operador Pleno'
        Description = 'Para quem já opera com consistência e quer crescer'
        PriceCents = 89700
    },
    [pscustomobject]@{
        Code = 'operador_senior'
        Name = 'Operador Sênior'
        Description = 'Para operações maduras que precisam de mais escala'
        PriceCents = 99700
    },
    [pscustomobject]@{
        Code = 'elite_i'
        Name = 'Elite I'
        Description = 'Para quem entrou no nível das grandes operações'
        PriceCents = 249700
    },
    [pscustomobject]@{
        Code = 'elite_ii'
        Name = 'Elite II'
        Description = 'Para operações de alta escala'
        PriceCents = 379700
    },
    [pscustomobject]@{
        Code = 'elite_iii'
        Name = 'Elite III'
        Description = 'Para operações de altíssima escala e grande volume'
        PriceCents = 749700
    }
)

function ConvertFrom-ProtectedValue {
    param([Parameter(Mandatory = $true)][Security.SecureString]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Test-PagarmeProductionSecretKey {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value -cmatch '^sk_[A-Za-z0-9]{16,509}$' -and
        -not $Value.StartsWith('sk_test_', [StringComparison]::Ordinal)
}

function Get-ObjectProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function New-PagarmeClient {
    param([Parameter(Mandatory = $true)][string]$SecretKey)

    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor
        [Net.DecompressionMethods]::Deflate
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    $credentialBytes = [Text.Encoding]::ASCII.GetBytes("${SecretKey}:")
    try {
        $authorization = [Convert]::ToBase64String($credentialBytes)
        $client.DefaultRequestHeaders.Authorization =
            [Net.Http.Headers.AuthenticationHeaderValue]::new('Basic', $authorization)
        $client.DefaultRequestHeaders.Accept.Add(
            [Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new('application/json')
        )
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('BlindouCatalogOperator/1.0')
        return $client
    }
    finally {
        [Array]::Clear($credentialBytes, 0, $credentialBytes.Length)
        $authorization = $null
    }
}

function Resolve-PagarmePlanUri {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -notmatch '^/plans(?:\?|$)') {
        throw 'O executor permite somente o recurso /plans.'
    }
    $baseUri = [Uri]::new("$apiBaseUri/")
    $resolved = [Uri]::new($baseUri, $Path.TrimStart('/'))
    if (
        $resolved.Scheme -cne 'https' -or
        $resolved.Host -cne 'api.pagar.me' -or
        -not $resolved.AbsolutePath.StartsWith('/core/v5/plans', [StringComparison]::Ordinal)
    ) {
        throw 'A URL resolvida saiu do endpoint fixo de planos Pagar.me.'
    }
    return $resolved
}

function Get-SafePagarmeErrorDetail {
    param([AllowNull()][string]$ResponseBody)

    if ([string]::IsNullOrWhiteSpace($ResponseBody)) { return 'sem detalhe estruturado' }
    try { $errorObject = $ResponseBody | ConvertFrom-Json } catch { return 'sem detalhe estruturado' }
    $parts = [Collections.Generic.List[string]]::new()
    $message = [string](Get-ObjectProperty -Object $errorObject -Name 'message')
    if (-not [string]::IsNullOrWhiteSpace($message)) { $parts.Add($message) }
    $errors = Get-ObjectProperty -Object $errorObject -Name 'errors'
    if ($null -ne $errors) {
        foreach ($property in @($errors.PSObject.Properties) | Select-Object -First 12) {
            foreach ($value in @($property.Value) | Select-Object -First 4) {
                $text = [string]$value
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $parts.Add("$($property.Name): $text")
                }
            }
        }
    }
    if ($parts.Count -eq 0) { return 'sem detalhe estruturado' }
    $detail = $parts -join '; '
    $detail = $detail -replace '(?i)\b(?:sk|pk)_(?:test_)?[A-Za-z0-9]{8,}\b', '<credencial-removida>'
    $detail = $detail -replace '(?i)\bBasic\s+[A-Za-z0-9+/=]{12,}\b', 'Basic <credencial-removida>'
    if ($detail.Length -gt 800) { $detail = $detail.Substring(0, 800) + '…' }
    return $detail
}

function Invoke-PagarmeJsonRequest {
    param(
        [Parameter(Mandatory = $true)][Net.Http.HttpClient]$Client,
        [Parameter(Mandatory = $true)][Net.Http.HttpMethod]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][object]$Body,
        [AllowNull()][string]$IdempotencyKey
    )

    $requestUri = Resolve-PagarmePlanUri -Path $Path
    $request = [Net.Http.HttpRequestMessage]::new($Method, $requestUri)
    try {
        if ($IdempotencyKey) {
            [void]$request.Headers.TryAddWithoutValidation('Idempotency-Key', $IdempotencyKey)
        }
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 12 -Compress
            $request.Content = [Net.Http.StringContent]::new(
                $json,
                [Text.Encoding]::UTF8,
                'application/json'
            )
        }
        try {
            $response = $Client.SendAsync($request).GetAwaiter().GetResult()
        }
        catch {
            throw 'Falha de rede ao acessar a API Pagar.me; nenhum retry automático foi executado.'
        }
        try {
            $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                $safeDetail = Get-SafePagarmeErrorDetail -ResponseBody $responseBody
                throw "Pagar.me recusou a operação em /plans com HTTP $([int]$response.StatusCode). Detalhe: $safeDetail"
            }
            if ([string]::IsNullOrWhiteSpace($responseBody)) {
                throw 'Pagar.me respondeu sem JSON na operação de planos.'
            }
            return $responseBody | ConvertFrom-Json
        }
        finally {
            $response.Dispose()
            $responseBody = $null
        }
    }
    finally {
        $request.Dispose()
        $json = $null
    }
}

function Get-AllPagarmePlans {
    param([Parameter(Mandatory = $true)][Net.Http.HttpClient]$Client)

    $plans = [Collections.Generic.List[object]]::new()
    for ($page = 1; $page -le 50; $page++) {
        $response = Invoke-PagarmeJsonRequest `
            -Client $Client `
            -Method ([Net.Http.HttpMethod]::Get) `
            -Path "/plans?page=$page&size=30" `
            -Body $null `
            -IdempotencyKey $null
        $dataProperty = $response.PSObject.Properties['data']
        if ($null -ne $dataProperty) {
            $pagePlans = @($dataProperty.Value)
        }
        elseif ($response -is [Array]) {
            $pagePlans = @($response)
        }
        else {
            throw 'A listagem de planos retornou um contrato desconhecido.'
        }
        foreach ($plan in $pagePlans) { $plans.Add($plan) }
        if ($pagePlans.Count -lt 30) { return $plans.ToArray() }
    }
    throw 'A listagem de planos excedeu o limite operacional de 1.500 itens.'
}

function New-BlindouPlanPayload {
    param([Parameter(Mandatory = $true)][object]$Spec)

    return [ordered]@{
        name = $Spec.Name
        description = $Spec.Description
        shippable = $false
        payment_methods = @('credit_card')
        installments = @(1)
        minimum_price = $Spec.PriceCents
        statement_descriptor = 'BLINDOU'
        currency = 'BRL'
        interval = 'month'
        interval_count = 1
        billing_type = 'prepaid'
        items = @(
            [ordered]@{
                name = $Spec.Name
                quantity = 1
                pricing_scheme = [ordered]@{
                    scheme_type = 'unit'
                    price = $Spec.PriceCents
                }
            }
        )
        metadata = [ordered]@{
            blindou_catalog = 'commercial'
            blindou_catalog_code = $Spec.Code
            blindou_catalog_version = $catalogVersion
        }
    }
}

function Assert-BlindouPlanMatchesSpec {
    param(
        [Parameter(Mandatory = $true)][object]$Plan,
        [Parameter(Mandatory = $true)][object]$Spec
    )

    $id = [string](Get-ObjectProperty -Object $Plan -Name 'id')
    if ($id -cnotmatch '^plan_[A-Za-z0-9]{16,64}$') {
        throw "Plano $($Spec.Code) possui ID externo inválido."
    }
    $checks = [ordered]@{
        name = [string](Get-ObjectProperty -Object $Plan -Name 'name') -ceq $Spec.Name
        description = [string](Get-ObjectProperty -Object $Plan -Name 'description') -ceq $Spec.Description
        status = [string](Get-ObjectProperty -Object $Plan -Name 'status') -ceq 'active'
        currency = [string](Get-ObjectProperty -Object $Plan -Name 'currency') -ceq 'BRL'
        interval = [string](Get-ObjectProperty -Object $Plan -Name 'interval') -ceq 'month'
        interval_count = [int64](Get-ObjectProperty -Object $Plan -Name 'interval_count') -eq 1
        minimum_price = [int64](Get-ObjectProperty -Object $Plan -Name 'minimum_price') -eq $Spec.PriceCents
        billing_type = [string](Get-ObjectProperty -Object $Plan -Name 'billing_type') -ceq 'prepaid'
        statement_descriptor = [string](Get-ObjectProperty -Object $Plan -Name 'statement_descriptor') -ceq 'BLINDOU'
        shippable = $null -eq (Get-ObjectProperty -Object $Plan -Name 'shippable') -or
            -not [bool](Get-ObjectProperty -Object $Plan -Name 'shippable')
    }
    foreach ($check in $checks.GetEnumerator()) {
        if (-not $check.Value) {
            throw "Plano $($Spec.Code) diverge no campo $($check.Key)."
        }
    }
    $trial = Get-ObjectProperty -Object $Plan -Name 'trial_period_days'
    if ($null -ne $trial -and [int64]$trial -ne 0) {
        throw "Plano $($Spec.Code) possui trial não autorizado."
    }
    $paymentMethods = @((Get-ObjectProperty -Object $Plan -Name 'payment_methods'))
    if (($paymentMethods | ForEach-Object { [string]$_ }) -join ',' -cne 'credit_card') {
        throw "Plano $($Spec.Code) possui meios de pagamento divergentes."
    }
    $installments = @((Get-ObjectProperty -Object $Plan -Name 'installments'))
    if (($installments | ForEach-Object { [int64]$_ }) -join ',' -ne '1') {
        throw "Plano $($Spec.Code) possui parcelamento divergente."
    }
    $items = @((Get-ObjectProperty -Object $Plan -Name 'items'))
    if ($items.Count -ne 1) { throw "Plano $($Spec.Code) deve possuir um item." }
    $item = $items[0]
    $pricingScheme = Get-ObjectProperty -Object $item -Name 'pricing_scheme'
    if (
        [string](Get-ObjectProperty -Object $item -Name 'name') -cne $Spec.Name -or
        [int64](Get-ObjectProperty -Object $item -Name 'quantity') -ne 1 -or
        [string](Get-ObjectProperty -Object $pricingScheme -Name 'scheme_type') -cne 'unit' -or
        [int64](Get-ObjectProperty -Object $pricingScheme -Name 'price') -ne $Spec.PriceCents
    ) {
        throw "Plano $($Spec.Code) possui item ou preço divergente."
    }
    $metadata = Get-ObjectProperty -Object $Plan -Name 'metadata'
    if (
        [string](Get-ObjectProperty -Object $metadata -Name 'blindou_catalog') -cne 'commercial' -or
        [string](Get-ObjectProperty -Object $metadata -Name 'blindou_catalog_code') -cne $Spec.Code -or
        [string](Get-ObjectProperty -Object $metadata -Name 'blindou_catalog_version') -cne $catalogVersion
    ) {
        throw "Plano $($Spec.Code) possui metadata divergente."
    }
}

function Find-BlindouPlan {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Plans,
        [Parameter(Mandatory = $true)][object]$Spec
    )

    $matches = @($Plans | Where-Object {
        $metadata = Get-ObjectProperty -Object $_ -Name 'metadata'
        [string](Get-ObjectProperty -Object $metadata -Name 'blindou_catalog_code') -ceq $Spec.Code -and
            [string](Get-ObjectProperty -Object $_ -Name 'status') -cne 'deleted'
    })
    if ($matches.Count -gt 1) {
        throw "Há mais de um plano vivo com o código $($Spec.Code); criação recusada."
    }
    if ($matches.Count -eq 1) {
        Assert-BlindouPlanMatchesSpec -Plan $matches[0] -Spec $Spec
        return $matches[0]
    }
    $nameCollisions = @($Plans | Where-Object {
        [string](Get-ObjectProperty -Object $_ -Name 'name') -ceq $Spec.Name -and
            [string](Get-ObjectProperty -Object $_ -Name 'status') -cne 'deleted'
    })
    if ($nameCollisions.Count -gt 0) {
        throw "Já existe plano vivo chamado $($Spec.Name) sem a identidade canônica do Blindou."
    }
    return $null
}

function Write-BlindouPlanReceipt {
    param(
        [Parameter(Mandatory = $true)][hashtable]$ResolvedPlans,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $receiptPlans = foreach ($spec in $catalog) {
        $plan = $ResolvedPlans[$spec.Code]
        [ordered]@{
            code = $spec.Code
            pagarme_plan_id = [string](Get-ObjectProperty -Object $plan -Name 'id')
            name = $spec.Name
            price_cents = $spec.PriceCents
        }
    }
    $receipt = [ordered]@{
        schema = 1
        provider = 'pagarme-v5'
        environment = 'production'
        catalog_version = $catalogVersion
        verified_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        plans = @($receiptPlans)
    }
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    $temporaryPath = "$Path.tmp"
    if (Test-Path -LiteralPath $temporaryPath) {
        throw "Recibo temporário inesperado: $temporaryPath"
    }
    try {
        $json = $receipt | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        $json = $null
    }
}

function Invoke-SelfTest {
    $productionFixture = 'sk_' + ('A' * 16)
    if (-not (Test-PagarmeProductionSecretKey $productionFixture)) {
        throw 'Self-test recusou formato de produção válido.'
    }
    foreach ($invalid in @(
        ('sk_test_' + ('A' * 16)),
        ('sk_live_' + ('A' * 16)),
        ('pk_' + ('A' * 16))
    )) {
        if (Test-PagarmeProductionSecretKey $invalid) {
            throw 'Self-test aceitou formato proibido.'
        }
    }
    $redactionFixture = '{"message":"key sk_' + ('A' * 16) + ' invalid"}'
    $safeFixture = Get-SafePagarmeErrorDetail -ResponseBody $redactionFixture
    if ($safeFixture -notmatch '<credencial-removida>' -or $safeFixture -match 'A{8}') {
        throw 'Self-test detectou falha na remoção de credencial do erro.'
    }
    $resolvedUri = Resolve-PagarmePlanUri -Path '/plans?page=1&size=30'
    if ($resolvedUri.AbsoluteUri -cne 'https://api.pagar.me/core/v5/plans?page=1&size=30') {
        throw 'Self-test detectou composição incorreta da URL de planos.'
    }
    $emptyList = '{"data":[],"paging":{"total":0}}' | ConvertFrom-Json
    $emptyDataProperty = $emptyList.PSObject.Properties['data']
    if ($null -eq $emptyDataProperty -or @($emptyDataProperty.Value).Count -ne 0) {
        throw 'Self-test não reconheceu a listagem vazia válida do Pagar.me.'
    }
    if ($catalog.Count -ne 7 -or ($catalog | Measure-Object -Property PriceCents -Sum).Sum -ne 1647900) {
        throw 'Self-test detectou divergência no catálogo de sete planos.'
    }
    $spec = $catalog[0]
    $plan = [pscustomobject]@{
        id = 'plan_ABCDEFGHIJKLMNOP'
        name = $spec.Name
        description = $spec.Description
        status = 'active'
        currency = 'BRL'
        interval = 'month'
        interval_count = 1
        minimum_price = $spec.PriceCents
        billing_type = 'prepaid'
        statement_descriptor = 'BLINDOU'
        payment_methods = @('credit_card')
        installments = @(1)
        items = @([pscustomobject]@{
            name = $spec.Name
            quantity = 1
            pricing_scheme = [pscustomobject]@{ scheme_type = 'unit'; price = $spec.PriceCents }
        })
        metadata = [pscustomobject]@{
            blindou_catalog = 'commercial'
            blindou_catalog_code = $spec.Code
            blindou_catalog_version = $catalogVersion
        }
    }
    $payloadFixture = New-BlindouPlanPayload -Spec $spec
    if ($payloadFixture.Contains('trial_period_days')) {
        throw 'Self-test detectou trial no payload de criação.'
    }
    Assert-BlindouPlanMatchesSpec -Plan $plan -Spec $spec
    if ($null -ne (Find-BlindouPlan -Plans @() -Spec $spec)) {
        throw 'Self-test encontrou plano em uma coleção vazia.'
    }
    $plan.minimum_price++
    try {
        Assert-BlindouPlanMatchesSpec -Plan $plan -Spec $spec
        throw 'Self-test não recusou preço divergente.'
    }
    catch {
        if ($_.Exception.Message -eq 'Self-test não recusou preço divergente.') { throw }
    }
    Write-Host 'Self-test do executor Pagar.me: aprovado.' -ForegroundColor Green
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

if (-not $ConfirmCreation) {
    throw 'Use -ConfirmCreation para autorizar a criação permanente dos planos live.'
}

foreach ($required in @($identity, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Arquivo administrativo ausente: $required"
    }
}

function Invoke-RemotePlanProvisioning {
    $remoteCommand =
        'sudo -n /usr/local/sbin/blindou-deployctl provision-pagarme-plans blindou-pagarme-plans'
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $argumentList = @(
            '-F NUL',
            "-i `"$identity`"",
            '-o IdentitiesOnly=yes',
            '-o StrictHostKeyChecking=yes',
            "-o UserKnownHostsFile=`"$knownHosts`"",
            $server,
            $remoteCommand
        ) -join ' '
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'ssh.exe'
        $startInfo.Arguments = $argumentList
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = $utf8Encoding
        $startInfo.StandardErrorEncoding = $utf8Encoding
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw 'Não foi possível iniciar o SSH seguro.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -eq 0) { return $stdout }
        if ($process.ExitCode -ne 2) {
            $safeError = ($stderr + "`n" + $stdout).Trim()
            $safeError = $safeError -replace
                '(?i)\b(?:sk|pk)_(?:test_)?[A-Za-z0-9]{8,}\b', '<credencial-removida>'
            if ($safeError.Length -gt 1200) { $safeError = $safeError.Substring(0, 1200) + '…' }
            throw "Provisionamento fechado dos planos falhou. $safeError"
        }
        if ($attempt -eq 12) {
            throw 'O controlador permaneceu ocupado por um minuto.'
        }
        Write-Host 'O coletor de métricas está usando o controlador; nova tentativa em 5 segundos.' `
            -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}

function Save-RemoteReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteOutput,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $receiptLine = @($RemoteOutput -split "`r?`n" | Where-Object {
        $_ -match '^pagarme_plans_receipt_base64='
    })
    if ($receiptLine.Count -ne 1) {
        throw 'O controlador não devolveu um único recibo dos planos.'
    }
    $encoded = $receiptLine[0].Substring('pagarme_plans_receipt_base64='.Length)
    try {
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
        $receipt = $json | ConvertFrom-Json
    }
    catch {
        throw 'O recibo devolvido pelo controlador não é JSON base64 válido.'
    }
    if (
        [int]$receipt.schema -ne 1 -or
        [string]$receipt.provider -cne 'pagarme-v5' -or
        [string]$receipt.environment -cne 'production' -or
        [string]$receipt.catalog_version -cne $catalogVersion -or
        @($receipt.plans).Count -ne 7
    ) {
        throw 'O recibo devolvido pelo controlador diverge do catálogo esperado.'
    }
    foreach ($spec in $catalog) {
        $entry = @($receipt.plans | Where-Object { $_.code -ceq $spec.Code })
        if (
            $entry.Count -ne 1 -or
            [string]$entry[0].pagarme_plan_id -cnotmatch '^plan_[A-Za-z0-9]{16,64}$' -or
            [int64]$entry[0].price_cents -ne $spec.PriceCents
        ) {
            throw "O recibo diverge no plano $($spec.Code)."
        }
    }
    if ($json -match '(?i)\b(?:sk|pk)_(?:test_)?[A-Za-z0-9]{8,}\b') {
        throw 'O recibo foi recusado porque contém material semelhante a credencial.'
    }
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force)
    }
    $temporaryPath = "$Path.tmp"
    if (Test-Path -LiteralPath $temporaryPath) {
        throw "Recibo temporário inesperado: $temporaryPath"
    }
    try {
        [IO.File]::WriteAllText($temporaryPath, $json, $utf8Encoding)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        $encoded = $null
        $json = $null
    }
}

try {
    try { $Host.UI.RawUI.WindowTitle = 'Blindou - sete planos Pagar.me de produção' } catch { }
    Write-Host 'Usando a secret key já guardada no cofre root-only do servidor.' -ForegroundColor Cyan
    $output = Invoke-RemotePlanProvisioning
    Save-RemoteReceipt -RemoteOutput $output -Path $ReceiptPath
    foreach ($line in $output -split "`r?`n") {
        if ($line -and $line -notmatch '^pagarme_plans_receipt_base64=') { Write-Host $line }
    }
    Write-Host 'Sete planos de produção conferidos; nenhuma chave foi solicitada ou copiada.' `
        -ForegroundColor Green
    Write-Host "Recibo não secreto: $ReceiptPath"
}
catch {
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
