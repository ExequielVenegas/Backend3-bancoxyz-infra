#requires -Version 7.0
$ErrorActionPreference='Stop'
$http=Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1'
$tokens=@{}; $issued=@{}
$ports=@{web=8081;mobile=8082;atm=8083}
$scopes=@{
 web='web.customers.write web.payments.read'
 mobile='mobile.read mobile.customers.read mobile.accounts.read mobile.accounts.write mobile.payments.read mobile.payments.write'
 atm='atm.read atm.customers.read atm.accounts.read atm.payments.read atm.payments.write'
}
function Token([string]$channel) {
 if(-not $tokens.ContainsKey($channel) -or ((Get-Date)-$issued[$channel]).TotalSeconds -gt 150) {
  $tokens[$channel]=& "$PSScriptRoot/Get-ChannelToken.ps1" -Channel $channel -Scope $scopes[$channel]
  $issued[$channel]=Get-Date
 }
 return $tokens[$channel]
}
function Request([string]$channel,[string]$method,[string]$route,$body=$null,[string]$key='') {
 $headers=@{Authorization="Bearer $(Token $channel)"}
 if($key) { $headers['Idempotency-Key']=$key }
 $options=@{Uri="https://localhost:$($ports[$channel])/api/$channel/$route";Method=$method;Headers=$headers}
 if($null -ne $body) { $options.JsonBody=$body|ConvertTo-Json -Depth 5 -Compress }
 & $http @options
}
function Check($r,[int]$expected,[string]$label) {
 if($r.StatusCode -ne $expected) { throw "$label : esperado $expected; recibido $($r.StatusCode)" }
 Write-Host "$label : HTTP $expected OK"
}
function WaitPayment([string]$channel,[string]$id,[string]$expected='APLICADO') {
 $deadline=(Get-Date).AddSeconds(120)
 do {
  $r=Request $channel GET "pagos/$id"; Check $r 200 "Resultado $channel"
  $data=$r.Content|ConvertFrom-Json
  if($data.estado -ne 'PENDIENTE') {
   if($data.estado -ne $expected) { throw "Estado inesperado: $($data.estado) / $($data.motivo)" }
   Write-Host "$channel : $($data.tipo) $expected / $($data.motivo)"; return $data
  }
  if((Get-Date) -ge $deadline) { throw "Pago $id sigue PENDIENTE; revisar Kafka/outbox sin crear otra orden" }
  Start-Sleep -Seconds 3
 } while($true)
}
foreach($channel in @('mobile','atm')) {
 $deadline=(Get-Date).AddSeconds(90)
 $route=if($channel -eq 'mobile'){'cuentas/137'}else{'cuentas/137/saldo'}
 do {
  $r=Request $channel GET $route
  if($r.StatusCode -eq 200) { break }
  if($r.StatusCode -notin @(502,503) -or (Get-Date) -ge $deadline) { throw "$channel no disponible: $($r.StatusCode)" }
  Start-Sleep -Seconds 5
 } while($true)
 Check $r 200 "Consulta legacy $channel"
 Check (& $http -Uri "https://localhost:$($ports[$channel])/api/$channel/$route") 401 "Sin token $channel"
}
Check (& $http -Uri 'https://localhost:8083/api/atm/cuentas/137/saldo' -Headers @{Authorization="Bearer $(Token mobile)"}) 401 'Token Mobile rechazado por ATM'
Check (& $http -Uri 'https://localhost:8082/api/mobile/cuentas/137' -Headers @{Authorization="Bearer $(Token web)"}) 401 'Token Web rechazado por Mobile'
$r=Request web POST clientes @{nombre='Titular demo canales EFT';email='canales@example.invalid';documento="DEMO-$([guid]::NewGuid().ToString().Substring(0,8))"} ([guid]::NewGuid().ToString())
Check $r 201 'Crear titular de demostracion'; $customer=($r.Content|ConvertFrom-Json).clienteId
$r=Request mobile GET "clientes/$customer"; Check $r 200 'Perfil Mobile'
if(($r.Content|ConvertFrom-Json).PSObject.Properties.Name -contains 'documento') { throw 'Mobile expuso documento' }
$r=Request atm GET "clientes/$customer"; Check $r 200 'Saludo ATM'
if(($r.Content|ConvertFrom-Json).PSObject.Properties.Name -contains 'email') { throw 'ATM expuso email' }
$accounts=@()
foreach($alias in @('Origen demo canales','Destino demo canales')) {
 $r=Request mobile POST 'cuentas-modernas' @{clienteId=$customer;tipo='AHORRO';alias=$alias} ([guid]::NewGuid().ToString())
 Check $r 201 'Apertura Mobile'; $accounts+=($r.Content|ConvertFrom-Json).cuentaId
}
Check (Request atm POST 'cuentas-modernas' @{clienteId=$customer;tipo='AHORRO';alias='No crear'} ([guid]::NewGuid().ToString())) 403 'ATM no administra cuentas'
$deposit=@{tipo='DEPOSITO';destino=$accounts[0];monto=100;referencia='Deposito sintetico ATM'}
Check (Request mobile POST pagos $deposit ([guid]::NewGuid().ToString())) 403 'Mobile no deposita efectivo'
$r=Request atm POST pagos $deposit ([guid]::NewGuid().ToString()); Check $r 202 'Deposito ATM'
$depositId=($r.Content|ConvertFrom-Json).pagoId; $null=WaitPayment atm $depositId
Check (Request web GET "pagos/$depositId") 404 'Orden aislada por cliente OAuth'
$transfer=@{tipo='TRANSFERENCIA';origen=$accounts[0];destino=$accounts[1];monto=30;referencia='Transferencia Mobile'}
Check (Request atm POST pagos $transfer ([guid]::NewGuid().ToString())) 403 'ATM no transfiere'
$r=Request mobile POST pagos $transfer ([guid]::NewGuid().ToString()); Check $r 202 'Transferencia Mobile'
$null=WaitPayment mobile (($r.Content|ConvertFrom-Json).pagoId)
$key=[guid]::NewGuid().ToString(); $withdraw=@{tipo='RETIRO';origen=$accounts[0];monto=20;referencia='Retiro sintetico ATM'}
$r=Request atm POST pagos $withdraw $key; Check $r 202 'Retiro ATM'; $withdrawalId=($r.Content|ConvertFrom-Json).pagoId
$null=WaitPayment atm $withdrawalId
$r=Request atm POST pagos $withdraw $key; Check $r 202 'Retiro repetido con misma clave'
if(($r.Content|ConvertFrom-Json).pagoId -ne $withdrawalId) { throw 'Retiro duplicado' }
$r=Request atm POST pagos @{tipo='RETIRO';origen=$accounts[0];monto=1000;referencia='Rechazo ATM'} ([guid]::NewGuid().ToString())
Check $r 202 'Orden retiro sin fondos'; $rejected=WaitPayment atm (($r.Content|ConvertFrom-Json).pagoId) RECHAZADO
if($rejected.motivo -ne 'SALDO_INSUFICIENTE') { throw 'Motivo de rechazo inesperado' }
$r=Request mobile POST pagos @{tipo='PAGO';origen=$accounts[0];destino=$accounts[1];monto=10;referencia='Pago Mobile'} ([guid]::NewGuid().ToString())
Check $r 202 'Pago Mobile'; $null=WaitPayment mobile (($r.Content|ConvertFrom-Json).pagoId)
foreach($account in $accounts) {
 $r=Request atm GET "cuentas-modernas/$account/saldo"; Check $r 200 'Saldo minimo ATM'
 $data=$r.Content|ConvertFrom-Json
 if($data.saldo -ne 40) { throw "Saldo incorrecto en $account" }
 if($data.PSObject.Properties.Name -contains 'clienteId') { throw 'ATM expuso titular en saldo' }
}
Write-Output "Canales validados. Titular $customer; origen $($accounts[0]); destino $($accounts[1]); saldos 40/40. Retiro $withdrawalId."
Write-Output 'Se conservaron datos sinteticos; no se modificaron saldos legacy ni se imprimieron secretos.'
