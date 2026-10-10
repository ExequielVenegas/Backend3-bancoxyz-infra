param([string]$KeytoolPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$envPath = Join-Path $projectRoot '.env'
$secretsPath = Join-Path $projectRoot 'secrets'
$keyPath = Join-Path $secretsPath 'auth-signing.p12'

if (-not $KeytoolPath) {
    $command = Get-Command keytool -ErrorAction SilentlyContinue
    if ($command) { $KeytoolPath = $command.Source }
    elseif ($env:JAVA_HOME) { $KeytoolPath = Join-Path $env:JAVA_HOME 'bin/keytool.exe' }
}
if (-not $KeytoolPath -or -not (Test-Path -LiteralPath $KeytoolPath)) {
    throw 'Indicar -KeytoolPath con la ruta a keytool.exe del JDK, o configurar JAVA_HOME.'
}
if (-not (Test-Path -LiteralPath $envPath)) {
    Copy-Item (Join-Path $projectRoot '.env.example') $envPath
}
$content = [IO.File]::ReadAllText($envPath)
function New-LocalSecret {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}
foreach ($name in @('AUTH_WEB_CLIENT_SECRET', 'AUTH_KEYSTORE_PASSWORD')) {
    $pattern = "(?m)^" + $name + "=(.*)$"
    $match = [regex]::Match($content, $pattern)
    if (-not $match.Success -or -not $match.Groups[1].Value.Trim()) {
        if ($name -eq 'AUTH_KEYSTORE_PASSWORD' -and (Test-Path -LiteralPath $keyPath)) {
            throw 'Existe la clave de firma pero falta su password. Restaurar el .env original; no se reemplazara la clave.'
        }
        $value = New-LocalSecret
        if ($match.Success) { $content = [regex]::Replace($content, $pattern, "$name=$value") }
        else { $content += [Environment]::NewLine + "$name=$value" + [Environment]::NewLine }
    }
}
[IO.File]::WriteAllText($envPath, $content, [Text.UTF8Encoding]::new($false))
$password = [regex]::Match($content, '(?m)^AUTH_KEYSTORE_PASSWORD=(.*)$').Groups[1].Value.Trim()
$previous = $env:BANCOXYZ_KEYTOOL_PASSWORD
try {
    $env:BANCOXYZ_KEYTOOL_PASSWORD = $password
    if (-not (Test-Path -LiteralPath $keyPath)) {
        New-Item -ItemType Directory -Path $secretsPath -Force | Out-Null
        & $KeytoolPath -genkeypair -alias jwt -keyalg RSA -keysize 3072 -sigalg SHA256withRSA -storetype PKCS12 -keystore $keyPath -storepass:env BANCOXYZ_KEYTOOL_PASSWORD -keypass:env BANCOXYZ_KEYTOOL_PASSWORD -dname 'CN=BancoXYZ JWT Local' -validity 3650 -noprompt
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo generar la clave de firma.' }
    }
    & $KeytoolPath -list -alias jwt -keystore $keyPath -storepass:env BANCOXYZ_KEYTOOL_PASSWORD *> $null
    if ($LASTEXITCODE -ne 0) { throw 'La clave existente no coincide con el password o no contiene el alias jwt.' }
} finally {
    $env:BANCOXYZ_KEYTOOL_PASSWORD = $previous
}
Write-Output 'Credenciales OAuth2 y clave de firma preparadas. Completar ACCOUNT_DB_* en .env antes de usar Compose.'
