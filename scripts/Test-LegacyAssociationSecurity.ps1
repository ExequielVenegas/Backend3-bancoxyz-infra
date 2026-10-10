#requires -Version 7.0
$ErrorActionPreference='Stop'
$uri='https://localhost:8081/api/web/cuentas-modernas/importaciones'
function Check($response,[int]$expected,[string]$label) {
    if($response.StatusCode -ne $expected) { throw "$label esperaba HTTP $expected, obtuvo $($response.StatusCode)" }
    Write-Output "$label : HTTP $expected OK"
}
Check (& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri $uri -Method POST -JsonBody '{}') 401 'Sin token'
$regular=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.accounts.write'
$import=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.accounts.import'
try {
    Check (& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri $uri -Method POST -Headers @{Authorization="Bearer $regular"} -JsonBody '{}') 403 'Permiso de apertura no permite importar'
    Check (& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri $uri -Method POST -Headers @{Authorization="Bearer $import"} -JsonBody '{}') 400 'Importacion exige decision completa'
    $body=@{legacyId=2147483647;clienteId=[guid]::NewGuid().ToString();archivoHash=('0'*64);linea=2;periodo='2026-10';tipoOrigen='ahorro';saldoOriginal=0;alias='Prueba negativa';motivo='Comprobacion tecnica con cliente inexistente';revisado=$true} | ConvertTo-Json -Compress
    Check (& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri $uri -Method POST -Headers @{Authorization="Bearer $import"} -JsonBody $body) 422 'Cliente inexistente impide asociacion'
    Check (& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri "$uri/2147483647" -Headers @{Authorization="Bearer $import"}) 404 'No se creo asociacion de prueba'
} finally { Remove-Variable regular,import -ErrorAction SilentlyContinue }
Write-Output 'Permisos y validacion verificados; no se importaron datos.'
