#requires -Version 7.0
param([Parameter(Mandatory = $true)][int]$CuentaId)
$ErrorActionPreference = 'Stop'
$compose = Join-Path (Split-Path $PSScriptRoot -Parent) 'compose.yaml'
$invoke = Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1'
$token = & (Join-Path $PSScriptRoot 'Get-WebToken.ps1')
$headers = @{Authorization="Bearer $token"}
$url = "https://localhost:8081/api/web/cuentas/$CuentaId"
function Read-Circuit {
    $result = & $invoke -Uri 'https://localhost:8081/actuator/info' -Headers $headers
    if ($result.StatusCode -ne 200) { throw 'No se pudo leer el estado del circuito' }
    return ($result.Content | ConvertFrom-Json).resilience.accountService.state
}
if ((& $invoke -Uri $url -Headers $headers).StatusCode -ne 200) {
    throw 'El flujo debe estar operativo antes de ejecutar la prueba.'
}
if ((Read-Circuit) -ne 'CLOSED') { throw 'Esperar la recuperacion del circuito antes de probar.' }
$paused = $false
try {
    docker compose -f $compose pause account-service
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo pausar Account.' }
    $paused = $true
    for ($i=0; $i -lt 4; $i++) {
        $response = & $invoke -Uri $url -Headers $headers
        if ($response.StatusCode -ne 503) { throw "Se esperaba 503, recibido $($response.StatusCode)" }
    }
    if ((Read-Circuit) -ne 'OPEN') { throw 'El circuito no se abrio tras los fallos.' }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $rejected = & $invoke -Uri $url -Headers $headers
    $timer.Stop()
    if ($rejected.StatusCode -ne 503 -or $timer.Elapsed.TotalSeconds -ge 3) {
        throw 'El circuito abierto no rechazo rapidamente la consulta.'
    }
    Write-Output 'OK: timeouts, respuesta 503 y circuito OPEN con rechazo rapido.'
} finally {
    if ($paused) {
        docker compose -f $compose unpause account-service
        if ($LASTEXITCODE -ne 0) { Write-Error 'Restaurar Account manualmente con docker compose unpause account-service.' }
    }
}
$deadline = (Get-Date).AddSeconds(60)
do {
    $response = & $invoke -Uri $url -Headers $headers
    if ($response.StatusCode -eq 200 -and (Read-Circuit) -eq 'CLOSED') {
        Write-Output 'OK: Account recuperado, respuesta 200 y circuito CLOSED.'
        exit 0
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
throw 'No se completo la recuperacion dentro de 60 segundos.'
