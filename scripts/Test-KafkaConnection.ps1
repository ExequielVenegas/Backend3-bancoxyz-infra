param([string]$BootstrapServer)
$ErrorActionPreference = 'Stop'
if (-not $BootstrapServer) { $BootstrapServer = $env:KAFKA_BOOTSTRAP_SERVERS }
if (-not $BootstrapServer) {
    $envPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
    if (Test-Path -LiteralPath $envPath) {
        $BootstrapServer = [regex]::Match([IO.File]::ReadAllText($envPath), '(?m)^KAFKA_BOOTSTRAP_SERVERS=(.*)$').Groups[1].Value.Trim()
    }
}
if (-not $BootstrapServer) { $BootstrapServer = '100.29.239.217:9093' }
$directory = Join-Path (Split-Path $PSScriptRoot -Parent) 'secrets/kafka'
foreach ($file in @('broker.crt', 'web.properties', 'account.properties')) {
    if (-not (Test-Path -LiteralPath (Join-Path $directory $file))) {
        throw "Falta secrets/kafka/$file"
    }
}
foreach ($user in @('web', 'account')) {
    docker run --rm --mount "type=bind,source=$directory,target=/secrets,readonly" --entrypoint /opt/kafka/bin/kafka-get-offsets.sh apache/kafka:4.1.2 --bootstrap-server $BootstrapServer --command-config "/secrets/$user.properties" --time latest --topic bancoxyz.cuentas.commands.v1
    if ($LASTEXITCODE -ne 0) { throw "Fallo TLS/SASL o permiso de descripcion para $user" }
    Write-Output "OK: $user conecta por SASL_SSL y puede consultar los offsets del topico principal."
}
Write-Output 'Validacion de conexion terminada. No se publicaron ni consumieron mensajes.'
