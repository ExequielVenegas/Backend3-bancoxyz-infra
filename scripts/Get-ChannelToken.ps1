param([ValidateSet('web','mobile','atm')][string]$Channel='mobile',[string]$Scope='')
$ErrorActionPreference='Stop'
if(-not $Scope) { $Scope="$Channel.read" }
$name='AUTH_'+$Channel.ToUpperInvariant()+'_CLIENT_SECRET'
$path=Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
$secret=[regex]::Match([IO.File]::ReadAllText($path),"(?m)^$name=([^`r`n]*)").Groups[1].Value.Trim()
if(-not $secret) { throw 'Preparar credenciales de canal antes de solicitar token.' }
$basic=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Channel}-demo:$secret"))
$response=& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri 'https://localhost:9000/oauth2/token' -Method POST -Headers @{Authorization="Basic $basic"} -Form @{grant_type='client_credentials';scope=$Scope}
if($response.StatusCode -ne 200) { throw "OAuth2 devolvio HTTP $($response.StatusCode)" }
return ($response.Content|ConvertFrom-Json).access_token
