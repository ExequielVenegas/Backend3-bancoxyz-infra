#requires -Version 7.0
param([Parameter(Mandatory)][string]$ReviewFile)
$ErrorActionPreference='Stop'
$review=Get-Content -LiteralPath $ReviewFile -Raw | ConvertFrom-Json
if($review.seleccion -cne 'SINTETICA_DEMO_V1') { throw 'Esta comprobacion requiere la seleccion sintetica.' }
$decisions=@($review.decisiones)
$token=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.accounts.read web.accounts.import'
$headers=@{Authorization="Bearer $token"}
$base='https://localhost:8081/api/web/cuentas-modernas'
try {
    $accounts=@(for($page=0;$page -lt 1000;$page++) {
        $r=& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri "${base}?page=$page&size=100" -Headers $headers
        if($r.StatusCode -ne 200) { throw "No se pudo consultar cuentas: HTTP $($r.StatusCode)" }
        $batch=@($r.Content | ConvertFrom-Json)
        $batch
        if($batch.Count -lt 100) { break }
    })
    [decimal]$total=0
    $results=@(foreach($d in $decisions) {
        $matches=@($accounts | Where-Object { $_.clienteId -eq $d.clienteId -and $_.alias -ceq $d.alias })
        if($matches.Count -ne 1) { throw "Legacy $($d.legacyId): se esperaba una unica cuenta sintetica." }
        $a=$matches[0]
        if($a.estado -ne 'BLOQUEADA' -or $a.tipo -ne 'AHORRO' -or $a.version -ne 0 -or [decimal]$a.saldo -ne [decimal]$d.saldoOriginal) {
            throw "Legacy $($d.legacyId): cuenta no coincide con su estado inicial esperado. No se cambiaron saldos."
        }
        $total += [decimal]$a.saldo
        [pscustomobject]@{legacyId=$d.legacyId;linea=$d.linea;clienteId=$d.clienteId;cuentaId=$a.cuentaId;saldo=$a.saldo;estado=$a.estado}
    })
    $first=$decisions[0]
    $lookup=& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri "$base/importaciones/$($first.legacyId)" -Headers $headers
    if($lookup.StatusCode -ne 200) { throw 'No se pudo leer la asociacion de muestra.' }
    $association=$lookup.Content | ConvertFrom-Json
    if($association.archivoHash -cne $first.archivoHash -or $association.linea -ne $first.linea -or $association.clienteId -ne $first.clienteId -or $association.motivo -cne $first.motivo) { throw 'La trazabilidad de la muestra no coincide.' }
    $body=[ordered]@{legacyId=[int]$first.legacyId;clienteId=$first.clienteId;archivoHash=$first.archivoHash;linea=[int]$first.linea;periodo=$first.periodo;tipoOrigen='ahorro';saldoOriginal=[decimal]$first.saldoOriginal;alias=$first.alias;motivo=$first.motivo;revisado=$true} | ConvertTo-Json -Compress
    $again=& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri "$base/importaciones" -Method POST -Headers $headers -JsonBody $body
    if($again.StatusCode -ne 201) { throw 'Fallo la repeticion idempotente de muestra.' }
    $same=$again.Content | ConvertFrom-Json
    if($same.cuentaId -ne $association.cuentaId -or [decimal]$same.saldo -ne [decimal]$first.saldoOriginal -or $same.version -ne 0) { throw 'La repeticion altero la cuenta.' }
    $output=Join-Path (Split-Path (Resolve-Path -LiteralPath $ReviewFile).Path -Parent) "resultado-sintetica-$($review.periodo).json"
    [ordered]@{seleccion='SINTETICA_DEMO_V1';periodo=$review.periodo;cuentas=$results.Count;saldoInicialTotal=$total;repeticionIdempotente=$true;asociaciones=$results} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $output -Encoding utf8
    Write-Output "OK: $($results.Count) cuentas sinteticas bloqueadas; saldo inicial total $total; repeticion sin duplicado."
    Write-Output "Resultado: $output"
} finally { Remove-Variable token -ErrorAction SilentlyContinue }
