#requires -Version 7.0
param(
 [ValidateSet('Preparar','Seguridad','Consultas','Deposito','Transferencia','Retiro','Duplicado','Pago','SinFondos','Resumen','Todo')][string]$Paso='Resumen',
 [ValidatePattern('^[a-zA-Z0-9_-]{1,60}$')][string]$Sesion='ensayo-eft'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$directory=Join-Path $root 'secrets/demo-eft'
$file=Join-Path $directory "$Sesion.json"
$http=Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1'
$ports=@{web=8081;mobile=8082;atm=8083}; $tokens=@{}; $issued=@{}
$scopes=@{
 web='web.read web.customers.read web.accounts.read web.accounts.write web.accounts.import web.payments.read web.payments.write'
 mobile='mobile.read mobile.customers.read mobile.accounts.read mobile.payments.read mobile.payments.write'
 atm='atm.read atm.customers.read atm.accounts.read atm.payments.read atm.payments.write'
}
function Token($channel) {
 if(-not $tokens.ContainsKey($channel) -or ((Get-Date)-$issued[$channel]).TotalSeconds -gt 150) {
  $tokens[$channel]=& "$PSScriptRoot/Get-ChannelToken.ps1" -Channel $channel -Scope $scopes[$channel]
  $issued[$channel]=Get-Date
 }
 $tokens[$channel]
}
function Request($channel,$method,$route,$body=$null,$key='') {
 $headers=@{Authorization="Bearer $(Token $channel)"}
 if($key){$headers['Idempotency-Key']=$key}
 $options=@{Uri="https://localhost:$($ports[$channel])/api/$channel/$route";Method=$method;Headers=$headers}
 if($null -ne $body){$options.JsonBody=$body|ConvertTo-Json -Depth 8 -Compress}
 & $http @options
}
function Check($response,$expected,$label) {
 if($response.StatusCode -ne $expected){throw "$label : HTTP $($response.StatusCode), esperado $expected"}
 Write-Host "$label : HTTP $expected OK"
}
function Save {
 $state|ConvertTo-Json -Depth 12|Set-Content -LiteralPath "$file.tmp" -Encoding utf8
 Move-Item -LiteralPath "$file.tmp" -Destination $file -Force
}
function Account($id) {
 $r=Request web GET "cuentas-modernas/$id"; Check $r 200 'Cuenta Web'; $r.Content|ConvertFrom-Json
}
function Summary {
 $a=Account $state.origen; $b=Account $state.destino
 [decimal]$expectedA=$state.inicialOrigen; [decimal]$expectedB=$state.inicialDestino
 foreach($op in $state.operaciones.Values) {
  if($op.estado -eq 'PENDIENTE'){throw 'Hay una orden pendiente; repetir su paso antes del resumen.'}
  if($op.estado -ne 'APLICADO'){continue}
  switch($op.body.tipo){
   DEPOSITO {$expectedA += [decimal]$op.body.monto}
   RETIRO {$expectedA -= [decimal]$op.body.monto}
   TRANSFERENCIA {$expectedA -= [decimal]$op.body.monto; $expectedB += [decimal]$op.body.monto}
   PAGO {$expectedA -= [decimal]$op.body.monto; $expectedB += [decimal]$op.body.monto}
  }
 }
 @([pscustomobject]@{Cuenta='Origen legacy 101';Inicial=$state.inicialOrigen;Esperado=$expectedA;Actual=$a.saldo},
   [pscustomobject]@{Cuenta='Destino legacy 102';Inicial=$state.inicialDestino;Esperado=$expectedB;Actual=$b.saldo})|Format-Table|Out-Host
 if([decimal]$a.saldo -ne $expectedA -or [decimal]$b.saldo -ne $expectedB){throw 'Saldos diferentes de los esperados; no se han corregido ni reiniciado.'}
 $state.ultimaVerificacion=(Get-Date).ToString('o'); Save
 Write-Host 'OK: saldos coinciden con las operaciones aplicadas de esta sesion.'
}
New-Item -ItemType Directory -Force $directory|Out-Null
# Evita dos ejecuciones simultaneas, incluso de sesiones distintas sobre las mismas cuentas.
$lock=$null
try {
 $lock=[IO.File]::Open((Join-Path $directory 'demo.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 if(Test-Path -LiteralPath $file){$state=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -AsHashtable}
 else {
  if($Paso -notin @('Preparar','Todo')){throw 'Ejecutar primero -Paso Preparar con la misma Sesion.'}
  $imports=Get-Content (Join-Path $root 'secrets/legacy-associations/resultado-sintetica-2026-10.json') -Raw|ConvertFrom-Json
  $origin=@($imports.asociaciones|Where-Object legacyId -eq 101)
  $destination=@($imports.asociaciones|Where-Object legacyId -eq 102)
  if($origin.Count -ne 1 -or $destination.Count -ne 1){throw 'Faltan las dos asociaciones sinteticas 101 y 102.'}
  $a=Account $origin[0].cuentaId; $b=Account $destination[0].cuentaId
  if($a.alias -notlike 'DEMO SINTETICA*' -or $b.alias -notlike 'DEMO SINTETICA*'){throw 'Solo se admiten las cuentas sinteticas.'}
  $state=@{sesion=$Sesion;creada=(Get-Date).ToString('o');origen=$a.cuentaId;destino=$b.cuentaId;clienteOrigen=$a.clienteId;inicialOrigen=$a.saldo;inicialDestino=$b.saldo;operaciones=@{}}
  Save
 }
 $steps=if($Paso -eq 'Todo'){@('Preparar','Seguridad','Consultas','Deposito','Transferencia','Retiro','Duplicado','Pago','SinFondos','Resumen')}else{@($Paso)}
 foreach($step in $steps) {
  Write-Host "`n=== $step | sesion $Sesion ==="
  switch($step) {
   Preparar {
    foreach($id in @($state.origen,$state.destino)) {
     $a=Account $id
     if($a.alias -notlike 'DEMO SINTETICA*'){throw 'La cuenta dejo de estar identificada como sintetica.'}
     if($a.estado -eq 'BLOQUEADA'){
      Check (Request web PUT "cuentas-modernas/$id" @{version=$a.version;alias=$a.alias;estado='ACTIVA'}) 200 'Activar cuenta sintetica'
     } elseif($a.estado -ne 'ACTIVA'){throw "Estado no permitido: $($a.estado)"}
    }
    Write-Host "Origen: $($state.origen)`nDestino: $($state.destino)"
    Summary
   }
   Seguridad {
    Check (& $http -Uri "https://localhost:8081/api/web/cuentas-modernas/$($state.origen)") 401 'Sin token'
    $limited=& "$PSScriptRoot/Get-ChannelToken.ps1" -Channel web -Scope 'web.read'
    Check (& $http -Uri "https://localhost:8081/api/web/cuentas-modernas/$($state.origen)" -Headers @{Authorization="Bearer $limited"}) 403 'Sin permiso de cuentas modernas'
    Check (& $http -Uri "https://localhost:8083/api/atm/cuentas-modernas/$($state.origen)/saldo" -Headers @{Authorization="Bearer $(Token mobile)"}) 401 'Token Mobile en ATM'
   }
   Consultas {
    foreach($channel in @('web','mobile','atm')) {
     $route="cuentas-modernas/$($state.origen)"; if($channel -eq 'atm'){$route+='/saldo'}
     $r=Request $channel GET $route; Check $r 200 "Contrato $channel"
     Write-Host $r.Content
     $r=Request $channel GET "clientes/$($state.clienteOrigen)"; Check $r 200 "Perfil $channel"
     $data=$r.Content|ConvertFrom-Json
     if($channel -eq 'mobile' -and $data.PSObject.Properties.Name -contains 'documento'){throw 'Mobile expuso documento'}
     if($channel -eq 'atm' -and $data.PSObject.Properties.Name -contains 'email'){throw 'ATM expuso email'}
     Write-Host $r.Content
    }
    $r=Request web GET 'cuentas-modernas/importaciones/101'; Check $r 200 'Trazabilidad CSV a cuenta'
    Write-Host $r.Content
   }
   Resumen {Summary}
   default {
    $operation=if($step -eq 'Duplicado'){'Retiro'}else{$step}
    if($step -eq 'Duplicado' -and -not $state.operaciones.ContainsKey('Retiro')){throw 'Ejecutar Retiro antes de Duplicado.'}
    if(-not $state.operaciones.ContainsKey($operation)) {
     $channel='atm'; $body=@{referencia="DEMO EFT $Sesion $operation"}
     switch($operation) {
      Deposito {$body.tipo='DEPOSITO';$body.destino=$state.origen;$body.monto=100}
      Transferencia {$channel='mobile';$body.tipo='TRANSFERENCIA';$body.origen=$state.origen;$body.destino=$state.destino;$body.monto=30}
      Retiro {$body.tipo='RETIRO';$body.origen=$state.origen;$body.monto=20}
      Pago {$channel='web';$body.tipo='PAGO';$body.origen=$state.origen;$body.destino=$state.destino;$body.monto=10}
      SinFondos {$body.tipo='RETIRO';$body.origen=$state.origen;$body.monto=([decimal](Account $state.origen).saldo+1000000)}
     }
     $state.operaciones[$operation]=@{key=[guid]::NewGuid().ToString();channel=$channel;body=$body;estado='PENDIENTE';pagoId=$null}
     Save # Clave y cuerpo persistidos ANTES del POST, incluso si se interrumpe la red.
    }
    $op=$state.operaciones[$operation]; $before=if($step -eq 'Duplicado'){(Account $state.origen).saldo}else{$null}
    $r=Request $op.channel POST pagos $op.body $op.key; Check $r 202 "$step aceptado"
    $data=$r.Content|ConvertFrom-Json
    if($op.pagoId -and $op.pagoId -ne $data.pagoId){throw 'La misma clave devolvio otra orden.'}
    $op.pagoId=$data.pagoId; Save
    Write-Host "pagoId: $($op.pagoId) | Idempotency-Key: $($op.key)"
    $deadline=(Get-Date).AddSeconds(120)
    do {
     $r=Request $op.channel GET "pagos/$($op.pagoId)"; Check $r 200 'Consultar resultado'
     $result=$r.Content|ConvertFrom-Json
     if($result.estado -ne 'PENDIENTE'){break}
     if((Get-Date) -ge $deadline){throw 'Orden PENDIENTE. Restaurar Kafka y repetir ESTE paso y sesion; no crear una nueva clave.'}
     Start-Sleep -Seconds 2
    }while($true)
    $expected=if($operation -eq 'SinFondos'){'RECHAZADO'}else{'APLICADO'}
    $op.estado=$result.estado; $op.motivo=$result.motivo; Save
    if($result.estado -ne $expected){throw "Esperado $expected; recibido $($result.estado): $($result.motivo)"}
    if($operation -eq 'SinFondos' -and $result.motivo -ne 'SALDO_INSUFICIENTE'){throw 'Motivo de rechazo incorrecto.'}
    Write-Host "Resultado: $($result.estado) / $($result.motivo)"
    if($step -eq 'Duplicado' -and [decimal](Account $state.origen).saldo -ne [decimal]$before){throw 'La repeticion cambio el saldo.'}
    Summary
   }
  }
 }
} finally {if($lock){$lock.Dispose()}; $tokens.Clear()}
