param([Parameter(Mandatory = $true)][int]$CuentaId)
$ErrorActionPreference = 'Stop'
$url = "https://localhost:8081/api/web/cuentas/$CuentaId"

function Assert-Status([string]$Uri, [hashtable]$Headers, [int]$Expected) {
    $actual = (& (Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1') -Uri $Uri -Headers $Headers).StatusCode
    if ($actual -ne $Expected) { throw "Esperado HTTP $Expected, recibido $actual para $Uri" }
    Write-Output "OK: HTTP $Expected"
}

Assert-Status $url @{} 401
Assert-Status $url @{Authorization='Bearer token-invalido'} 401
$limitedToken = & (Join-Path $PSScriptRoot 'Get-WebToken.ps1') -Scope 'web.info'
Assert-Status $url @{Authorization="Bearer $limitedToken"} 403
$readToken = & (Join-Path $PSScriptRoot 'Get-WebToken.ps1') -Scope 'web.read'
Assert-Status $url @{Authorization="Bearer $readToken"} 200
Assert-Status 'https://localhost:8081/actuator/info' @{Authorization="Bearer $readToken"} 403
Write-Output 'Seguridad Web verificada: autenticacion JWT y autorizacion por scopes.'
