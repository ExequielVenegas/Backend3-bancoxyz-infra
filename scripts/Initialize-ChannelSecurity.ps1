#requires -Version 7.0
$ErrorActionPreference='Stop'
$path=Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
$content=[IO.File]::ReadAllText($path)
foreach($name in @('AUTH_MOBILE_CLIENT_SECRET','AUTH_ATM_CLIENT_SECRET')) {
 $match=[regex]::Match($content,"(?m)^$name=([^`r`n]*)")
 if($match.Success -and $match.Groups[1].Value.Trim().Length -ge 32) { continue }
 if($match.Success -and $match.Groups[1].Value.Trim()) { throw "Secreto existente demasiado corto: $name. No se reemplaza automaticamente." }
 $value=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
 if($match.Success) { $content=[regex]::Replace($content,"(?m)^$name=[^`r`n]*","$name=$value") }
 else { $content=$content.TrimEnd()+[Environment]::NewLine+"$name=$value"+[Environment]::NewLine }
}
[IO.File]::WriteAllText($path,$content,[Text.UTF8Encoding]::new($false))
Write-Output 'Credenciales separadas de Mobile/ATM preparadas en .env, sin imprimir secretos.'
