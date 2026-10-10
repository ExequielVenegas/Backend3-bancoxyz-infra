#requires -Version 7.0
param([switch]$QueueOnly)
$ErrorActionPreference='Stop'
$http=Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1'
$base='https://localhost:8081/api/web'
$scope='web.customers.write web.accounts.read web.accounts.write web.payments.read web.payments.write'
$script:token=$null; $script:tokenTime=[datetime]::MinValue
function Request([string]$method,[string]$route,$body=$null,[string]$key='') {
 if(-not $script:token -or ((Get-Date)-$script:tokenTime).TotalSeconds -gt 180) {
  $script:token=& "$PSScriptRoot/Get-WebToken.ps1" -Scope $scope
  $script:tokenTime=Get-Date
 }
 $headers=@{Authorization="Bearer $script:token"}
 if($key) { $headers['Idempotency-Key']=$key }
 $requestOptions=@{Uri="$base/$route"; Method=$method; Headers=$headers}
 if($null -ne $body) { $requestOptions.JsonBody=$body|ConvertTo-Json -Depth 5 -Compress }
 & $http @requestOptions
}
function Check($response,[int]$expected,[string]$step) {
 if($response.StatusCode -ne $expected) { throw "$step : esperado $expected, recibido $($response.StatusCode)" }
 Write-Host "$step : HTTP $expected OK"
}
function WaitResult([string]$id,[string]$expected) {
 $deadline=(Get-Date).AddSeconds(120)
 do {
  $r=Request GET "pagos/$id"; Check $r 200 'Consulta de resultado'
  $payment=$r.Content|ConvertFrom-Json
  if($payment.estado -ne 'PENDIENTE') {
   if($payment.estado -ne $expected) { throw "Resultado inesperado: $($payment.estado), $($payment.motivo)" }
   Write-Host "Orden $id : $expected / $($payment.motivo)"; return $payment
  }
  if((Get-Date) -ge $deadline) { throw "Orden $id sigue PENDIENTE. Revisar Kafka, ACL, outbox y DLT. No reenviar con otra clave." }
  Start-Sleep -Seconds 3
 } while($true)
}
function Submit($body) {
 $r=Request POST pagos $body ([guid]::NewGuid().ToString()); Check $r 202 'Orden aceptada'
 return ($r.Content|ConvertFrom-Json)
}
$deadline=(Get-Date).AddSeconds(90)
do {
 $ready=Request GET pagos
 if($ready.StatusCode -eq 200) { break }
 if($ready.StatusCode -ne 503 -or (Get-Date) -ge $deadline) { throw "Pagos no disponible: HTTP $($ready.StatusCode)" }
 Start-Sleep -Seconds 5
} while($true)
Check (& $http -Uri "$base/pagos") 401 'Sin autenticacion'
$limited=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.read'
Check (& $http -Uri "$base/pagos" -Headers @{Authorization="Bearer $limited"}) 403 'Permiso legacy insuficiente'
$r=Request POST clientes @{nombre='Titular sintetico Pagos EFT'; email='pagos@example.invalid'} ([guid]::NewGuid().ToString())
Check $r 201 'Titular de demostracion'; $customer=($r.Content|ConvertFrom-Json).clienteId
$ids=@()
foreach($alias in @('Origen demo pagos','Destino demo pagos')) {
 $r=Request POST 'cuentas-modernas' @{clienteId=$customer; tipo='AHORRO'; alias=$alias} ([guid]::NewGuid().ToString())
 Check $r 201 'Cuenta de demostracion'; $ids+=($r.Content|ConvertFrom-Json).cuentaId
}
$deposit=@{tipo='DEPOSITO'; destino=$ids[0]; monto=100; referencia='Fondos sinteticos EFT'}
$key=[guid]::NewGuid().ToString()
$r=Request POST pagos $deposit $key; Check $r 202 'Deposito aceptado'
$payment=$r.Content|ConvertFrom-Json
$r=Request POST pagos $deposit $key; Check $r 202 'Reintento con misma clave'
if(($r.Content|ConvertFrom-Json).pagoId -ne $payment.pagoId) { throw 'Orden duplicada' }
$changed=@{tipo='DEPOSITO'; destino=$ids[0]; monto=101; referencia='Fondos sinteticos EFT'}
Check (Request POST pagos $changed $key) 409 'Conflicto de clave'
Check (Request POST pagos @{tipo='DEPOSITO'; destino=$ids[0]; monto=0; referencia='Invalido'} ([guid]::NewGuid().ToString())) 400 'Monto invalido'
if($QueueOnly) {
 $r=Request GET "pagos/$($payment.pagoId)"; Check $r 200 'Orden persistida'
 $current=$r.Content|ConvertFrom-Json
 if($current.estado -ne 'PENDIENTE') { throw 'La orden ya se proceso; QueueOnly requiere transporte de Pagos desactivado' }
 $r=Request GET "cuentas-modernas/$($ids[0])"; Check $r 200 'Saldo consultado'
 if(($r.Content|ConvertFrom-Json).saldo -ne 0) { throw 'El saldo cambio antes del procesamiento' }
 Write-Output "Registro y cola local verificados. Pago PENDIENTE: $($payment.pagoId)"
 Write-Output "Cuenta sintetica origen: $($ids[0]); destino: $($ids[1])"
 Write-Output 'Kafka y el procesamiento remoto NO se validaron. La orden se aplicara al activar el transporte.'
 return
}
$null=WaitResult $payment.pagoId APLICADO
$transfer=Submit @{tipo='TRANSFERENCIA'; origen=$ids[0]; destino=$ids[1]; monto=30; referencia='Transferencia demo EFT'}
$null=WaitResult $transfer.pagoId APLICADO
$pay=Submit @{tipo='PAGO'; origen=$ids[0]; destino=$ids[1]; monto=10; referencia='Pago beneficiario demo EFT'}
$null=WaitResult $pay.pagoId APLICADO
$rejected=Submit @{tipo='TRANSFERENCIA'; origen=$ids[0]; destino=$ids[1]; monto=1000; referencia='Prueba saldo insuficiente'}
$result=WaitResult $rejected.pagoId RECHAZADO
if($result.motivo -ne 'SALDO_INSUFICIENTE') { throw 'Motivo de rechazo inesperado' }
$r=Request GET "cuentas-modernas/$($ids[0])"; Check $r 200 'Saldo origen'; $origin=$r.Content|ConvertFrom-Json
$r=Request GET "cuentas-modernas/$($ids[1])"; Check $r 200 'Saldo destino'; $destination=$r.Content|ConvertFrom-Json
if($origin.saldo -ne 60 -or $destination.saldo -ne 40) { throw 'Saldos finales incorrectos' }
Check (Request POST "cuentas-modernas/$($ids[0])/cierre" @{version=$origin.version}) 409 'Cierre con saldo rechazado'
Write-Output "Flujo completo validado. Origen $($ids[0]): 60 CLP; destino $($ids[1]): 40 CLP. Datos sinteticos conservados."
