#requires -Version 7.0
param([string]$MysqlPath = 'C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe')
$ErrorActionPreference = 'Stop'
$path = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
if (-not (Test-Path $MysqlPath)) { throw 'Indicar -MysqlPath con la ruta del cliente mysql.exe' }
$content = [IO.File]::ReadAllText($path)
function EnvValue([string]$name) {
    return [regex]::Match($content, "(?m)^$name=([^`r`n]*)").Groups[1].Value.Trim()
}
$admin = EnvValue 'ACCOUNT_DB_USERNAME'
$adminPassword = EnvValue 'ACCOUNT_DB_PASSWORD'
if (-not $admin) { throw 'Falta ACCOUNT_DB_USERNAME en .env para preparar el esquema local' }
$password = EnvValue 'PAYMENT_DB_PASSWORD'
if (-not $password) { $password = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant() }
if ($password -notmatch '^[a-f0-9]{64}$') { throw 'La credencial PAYMENT existente no fue generada por este script; no se modificara' }
$values = @{
    PAYMENT_DB_URL='jdbc:mysql://host.docker.internal:3306/bancoxyz_payments'
    PAYMENT_DB_USERNAME='bancoxyz_payment'
    PAYMENT_DB_PASSWORD=$password
}
# Guardar la clave antes de preparar MySQL permite reintentar una inicializacion parcial.
foreach ($name in $values.Keys) {
    $line = "$name=$($values[$name])"
    if ($content -match "(?m)^$name=") { $content = [regex]::Replace($content, "(?m)^$name=[^`r`n]*", $line) }
    else { $content = $content.TrimEnd() + [Environment]::NewLine + $line + [Environment]::NewLine }
}
[IO.File]::WriteAllText($path,$content,[Text.UTF8Encoding]::new($false))
$sql = @"
CREATE DATABASE IF NOT EXISTS bancoxyz_payments CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS 'bancoxyz_payment'@'%' IDENTIFIED BY '$password';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES ON bancoxyz_payments.* TO 'bancoxyz_payment'@'%';
"@
$info = [Diagnostics.ProcessStartInfo]::new($MysqlPath)
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.RedirectStandardInput=$true
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
foreach ($arg in @('--no-defaults','--host=127.0.0.1','--port=3306',"--user=$admin",'--batch','--skip-column-names')) { $info.ArgumentList.Add($arg) }
# La clave administrativa solo se pasa al entorno del proceso hijo, nunca como argumento.
$info.Environment['MYSQL_PWD']=$adminPassword
$process=[Diagnostics.Process]::Start($info)
$output=$process.StandardOutput.ReadToEndAsync()
$errors=$process.StandardError.ReadToEndAsync()
$process.StandardInput.WriteLine($sql)
$process.StandardInput.Close()
$process.WaitForExit()
$null=$output.GetAwaiter().GetResult()
$null=$errors.GetAwaiter().GetResult()
$code=$process.ExitCode
$process.Dispose()
if ($code -ne 0) { throw 'MySQL no completo la preparacion. Verificar servicio local y permisos CREATE DATABASE/CREATE USER/GRANT del usuario administrativo. No se imprimieron credenciales.' }
Write-Output 'Esquema bancoxyz_payments y usuario dedicado preparados. lab_batch no fue modificado. Secretos guardados en .env.'
