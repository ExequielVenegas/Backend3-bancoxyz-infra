#requires -Version 7.0
$ErrorActionPreference='Stop'
$http=Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1'
$base='https://localhost:8081/api/web/clientes'
function Check($response,[int]$expected,[string]$step) {
    if($response.StatusCode -ne $expected) { throw "$step : esperado $expected, recibido $($response.StatusCode)" }
    Write-Output "$step : HTTP $expected OK"
}
$token=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.customers.read web.customers.write'
$limited=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.read'
$key=[guid]::NewGuid().ToString()
$headers=@{Authorization="Bearer $token"; 'Idempotency-Key'=$key}
$profile=@{nombre='Cliente EFT Demo'; documento="DEMO-$($key.Substring(0,8))"; email='demo@example.invalid'}
$body=$profile|ConvertTo-Json -Compress
Check (& $http -Uri $base) 401 'Sin autenticacion'
Check (& $http -Uri $base -Headers @{Authorization="Bearer $limited"}) 403 'Sin permiso Clientes'
$created=& $http -Uri $base -Method POST -Headers $headers -JsonBody $body
Check $created 201 'Alta'
$customer=$created.Content|ConvertFrom-Json
$repeated=& $http -Uri $base -Method POST -Headers $headers -JsonBody $body
Check $repeated 201 'Reintento idempotente'
if(($repeated.Content|ConvertFrom-Json).clienteId -ne $customer.clienteId) { throw 'El reintento creo otro cliente' }
$uri="$base/$($customer.clienteId)"
Check (& $http -Uri $uri -Headers $headers) 200 'Consulta persistida'
$profile.nombre='Cliente EFT Demo actualizado'
$update=@{version=$customer.version; perfil=$profile}|ConvertTo-Json -Depth 4 -Compress
Check (& $http -Uri $uri -Method PUT -Headers $headers -JsonBody $update) 200 'Actualizacion'
Check (& $http -Uri $uri -Method PUT -Headers $headers -JsonBody $update) 409 'Version obsoleta rechazada'
Check (& $http -Uri $base -Method POST -Headers $headers -JsonBody $body.Replace('Cliente EFT Demo','Otro nombre')) 409 'Clave reutilizada con contenido distinto'
$invalidHeaders=@{Authorization="Bearer $token"; 'Idempotency-Key'=[guid]::NewGuid().ToString()}
Check (& $http -Uri $base -Method POST -Headers $invalidHeaders -JsonBody '{"nombre":"","email":"invalido"}') 400 'Validacion del dominio'
Write-Output "Cliente sintetico conservado para consultar: $($customer.clienteId)"
Write-Output 'No se imprimieron tokens ni se modificaron cuentas o saldos legacy.'
