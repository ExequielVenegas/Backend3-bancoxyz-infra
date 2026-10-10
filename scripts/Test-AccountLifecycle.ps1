#requires -Version 7.0
$ErrorActionPreference='Stop'
$http=Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1'
$base='https://localhost:8081/api/web/cuentas-modernas'
function Check($response,[int]$expected,[string]$step) {
 if($response.StatusCode -ne $expected) { throw "$step : esperado $expected, recibido $($response.StatusCode)" }
 Write-Output "$step : HTTP $expected OK"
}
$token=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.customers.write web.accounts.read web.accounts.write'
$limited=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.read'
$headers=@{Authorization="Bearer $token"}
# Esperar descubrimiento sin reintentar escrituras con claves nuevas.
$deadline=(Get-Date).AddSeconds(90)
do {
 $ready=& $http -Uri $base -Headers $headers
 if($ready.StatusCode -eq 200) { break }
 if($ready.StatusCode -ne 503 -or (Get-Date) -ge $deadline) { throw "Cuentas no disponible: HTTP $($ready.StatusCode)" }
 Start-Sleep -Seconds 5
} while($true)
Check (& $http -Uri $base) 401 'Sin autenticacion'
Check (& $http -Uri $base -Headers @{Authorization="Bearer $limited"}) 403 'Permiso legacy insuficiente'
$customerHeaders=@{Authorization="Bearer $token"; 'Idempotency-Key'=[guid]::NewGuid().ToString()}
$created=& $http -Uri 'https://localhost:8081/api/web/clientes' -Method POST -Headers $customerHeaders -JsonBody '{"nombre":"Titular demo Cuentas EFT","email":"cuentas@example.invalid"}'
Check $created 201 'Perfil titular sintetico'
$customer=($created.Content|ConvertFrom-Json).clienteId
$openHeaders=@{Authorization="Bearer $token"; 'Idempotency-Key'=[guid]::NewGuid().ToString()}
$body=@{clienteId=$customer; tipo='AHORRO'; alias='Ahorro demo EFT'}|ConvertTo-Json -Compress
$opened=& $http -Uri $base -Method POST -Headers $openHeaders -JsonBody $body
Check $opened 201 'Apertura'
$account=$opened.Content|ConvertFrom-Json
if($account.saldo -ne 0 -or $account.clienteId -ne $customer -or $account.estado -ne 'ACTIVA') { throw 'Datos iniciales de cuenta incorrectos' }
$again=& $http -Uri $base -Method POST -Headers $openHeaders -JsonBody $body
Check $again 201 'Apertura repetida'
if(($again.Content|ConvertFrom-Json).cuentaId -ne $account.cuentaId) { throw 'La apertura se duplico' }
Check (& $http -Uri $base -Method POST -Headers $openHeaders -JsonBody $body.Replace('Ahorro demo EFT','Otro contenido')) 409 'Conflicto de idempotencia'
$uri="$base/$($account.cuentaId)"
Check (& $http -Uri $uri -Headers $headers) 200 'Consulta'
$changed=& $http -Uri $uri -Method PUT -Headers $headers -JsonBody '{"version":0,"alias":"Reserva demo","estado":"BLOQUEADA"}'
Check $changed 200 'Mantenimiento y bloqueo'
if(($changed.Content|ConvertFrom-Json).estado -ne 'BLOQUEADA') { throw 'Estado no persistido' }
Check (& $http -Uri $uri -Method PUT -Headers $headers -JsonBody '{"version":0,"alias":"Version vieja","estado":"ACTIVA"}') 409 'Version antigua rechazada'
Check (& $http -Uri $uri -Method PUT -Headers $headers -JsonBody '{"version":1,"alias":"Reserva demo","estado":"ACTIVA"}') 200 'Desbloqueo'
$closed=& $http -Uri "$uri/cierre" -Method POST -Headers $headers -JsonBody '{"version":2}'
Check $closed 200 'Cierre con saldo cero'
if(($closed.Content|ConvertFrom-Json).estado -ne 'CERRADA') { throw 'Cierre no persistido' }
Check (& $http -Uri $uri -Method PUT -Headers $headers -JsonBody '{"version":3,"alias":"No reabrir","estado":"ACTIVA"}') 409 'Reapertura rechazada'
$missingHeaders=@{Authorization="Bearer $token"; 'Idempotency-Key'=[guid]::NewGuid().ToString()}
$missing=@{clienteId=[guid]::NewGuid().ToString(); tipo='AHORRO'; alias='No crear'}|ConvertTo-Json -Compress
Check (& $http -Uri $base -Method POST -Headers $missingHeaders -JsonBody $missing) 422 'Titular inexistente rechazado'
Write-Output "Cuenta sintetica conservada (cerrada): $($account.cuentaId)"
Write-Output "Titular sintetico: $customer"
Write-Output 'No se modificaron cuentas legacy ni saldos migrados. No se imprimieron tokens.'
