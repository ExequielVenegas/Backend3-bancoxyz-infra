param(
    [string]$Scope = 'web.read web.info',
    [string]$TokenUri = 'https://localhost:9000/oauth2/token'
)
$ErrorActionPreference = 'Stop'
# Usar solo con el servidor local. El resultado es sensible: asignarlo a una variable.
$secret = $env:AUTH_WEB_CLIENT_SECRET
if (-not $secret) {
    $path = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
    if (Test-Path -LiteralPath $path) {
        $secret = [regex]::Match([IO.File]::ReadAllText($path), '(?m)^AUTH_WEB_CLIENT_SECRET=(.*)$').Groups[1].Value.Trim()
    }
}
if (-not $secret) { throw 'Falta AUTH_WEB_CLIENT_SECRET. Ejecutar Initialize-LocalSecurity.ps1.' }
$basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("web-demo:$secret"))
$response = & (Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1') -Uri $TokenUri -Method POST -Headers @{Authorization="Basic $basic"} -Form @{grant_type='client_credentials'; scope=$Scope}
if ($response.StatusCode -ne 200) { throw "OAuth2 devolvio HTTP $($response.StatusCode)" }
return ($response.Content | ConvertFrom-Json).access_token
