#requires -Version 7.0
param(
    [int]$CuentaId = 137,
    [ValidateRange(2000,2100)][int]$Anio = 2026,
    [guid]$IdempotencyKey = [guid]::NewGuid(),
    [int]$TimeoutSeconds = 90
)
$ErrorActionPreference = 'Stop'
$http = Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1'
$token = & (Join-Path $PSScriptRoot 'Get-WebToken.ps1') -Scope 'web.read web.write'
$headers = @{Authorization="Bearer $token"; 'Idempotency-Key'=$IdempotencyKey.ToString()}
$body = @{anio=$Anio} | ConvertTo-Json -Compress
$uri = "https://localhost:8081/api/web/cuentas/$CuentaId/solicitudes-estado"
# Esta prueba agrega una solicitud de demostracion; no cambia las tablas ETL ni saldos.
Write-Output "Idempotency-Key: $IdempotencyKey (conservar para reintentar la misma solicitud)"
$accepted = & $http -Uri $uri -Method POST -Headers $headers -JsonBody $body
if ($accepted.StatusCode -ne 202) { throw "POST: HTTP $($accepted.StatusCode). Reintentar con la misma clave; no generar una nueva." }
$first = $accepted.Content | ConvertFrom-Json
Write-Output "OK: POST aceptado por Kafka. Solicitud: $($first.solicitudId)"
function Wait-Persisted {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $response = & $http -Uri "https://localhost:8081$($first.consulta)" -Headers $headers
        if ($response.StatusCode -eq 200) { return ($response.Content | ConvertFrom-Json) }
        if ($response.StatusCode -notin @(404,503)) { throw "Consulta: HTTP $($response.StatusCode)" }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "No se confirmo MySQL. Revisar consumidor/DLT y conservar la clave $IdempotencyKey."
}
$saved = Wait-Persisted
if ($saved.estado -ne 'REGISTRADA' -or $saved.cuentaId -ne $CuentaId -or $saved.anio -ne $Anio) { throw 'Persistencia no coincide con solicitud' }
Write-Output 'OK: consumidor Account confirmo persistencia REGISTRADA en MySQL.'
$again = & $http -Uri $uri -Method POST -Headers $headers -JsonBody $body
if ($again.StatusCode -ne 202 -or ($again.Content | ConvertFrom-Json).solicitudId -ne $first.solicitudId) { throw 'El reenvio no conserva la identidad' }
# Esperar la evidencia del consumidor, no solo volver a leer una fila que ya existia.
$compose = Join-Path (Split-Path $PSScriptRoot -Parent) 'compose.yaml'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    $log = docker compose -f $compose logs --since 5m --no-color account-service 2>&1 |
        Select-String -SimpleMatch "Solicitud $($first.solicitudId) DUPLICADA_IGNORADA"
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo comprobar el consumidor' }
    if ($log) { break }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
if (-not $log) { throw 'No se observo consumo del duplicado dentro del plazo' }
$after = Wait-Persisted
if ($after.recibidaEn -ne $saved.recibidaEn) { throw 'La fecha original cambio al reenviar' }
Write-Output 'OK: consumidor detecto DUPLICADA_IGNORADA; conserva la solicitud y la fecha original.'
Write-Output "Consulta: https://localhost:8081$($first.consulta)"
Write-Output 'Flujo completo verificado: BFF Web -> Kafka AWS -> Account -> MySQL.'
