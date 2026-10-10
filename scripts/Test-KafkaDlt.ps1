#requires -Version 7.0
param([string]$BootstrapServer, [int]$TimeoutSeconds = 60)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $BootstrapServer) { $BootstrapServer = $env:KAFKA_BOOTSTRAP_SERVERS }
if (-not $BootstrapServer) {
    $BootstrapServer = [regex]::Match([IO.File]::ReadAllText((Join-Path $root '.env')), '(?m)^KAFKA_BOOTSTRAP_SERVERS=(.*)$').Groups[1].Value.Trim()
}
if (-not $BootstrapServer) { throw 'Falta KAFKA_BOOTSTRAP_SERVERS' }
$secrets = Join-Path $root 'secrets/kafka'
$topic = 'bancoxyz.cuentas.commands.v1'
$dlt = "$topic.dlt"
function Get-DltOffset {
    $lines = docker run --rm --mount "type=bind,source=$secrets,target=/secrets,readonly" --entrypoint /opt/kafka/bin/kafka-get-offsets.sh apache/kafka:4.1.2 --bootstrap-server $BootstrapServer --command-config /secrets/account.properties --topic $dlt --time latest
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar el offset DLT' }
    $line = @($lines | Where-Object { $_ -match '^bancoxyz\.cuentas\.commands\.v1\.dlt:0:\d+$' })
    if ($line.Count -ne 1) { throw 'Se esperaba una particion DLT' }
    return [long]($line[0].Split(':')[-1])
}
$before = Get-DltOffset
$id = [guid]::NewGuid().ToString()
# JSON legible, contrato invalido: solo se admite version 1.
$message = @{solicitudId=$id; version=99; tipo='SOLICITAR_ESTADO_CUENTA'; cliente='prueba-dlt'; cuentaId=137; anio=2026} | ConvertTo-Json -Compress
"$id|$message" | docker run --rm -i --mount "type=bind,source=$secrets,target=/secrets,readonly" --entrypoint /opt/kafka/bin/kafka-console-producer.sh apache/kafka:4.1.2 --bootstrap-server $BootstrapServer --producer.config /secrets/web.properties --topic $topic --property parse.key=true --property 'key.separator=|' --producer-property max.block.ms=10000 --producer-property request.timeout.ms=5000 --producer-property delivery.timeout.ms=10000 --sync
if ($LASTEXITCODE -ne 0) { throw 'Fallo la publicacion del mensaje de prueba' }
Write-Output "Mensaje invalido publicado: $id (version=99)"
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    $after = Get-DltOffset
    if ($after -gt $before) { break }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
if ($after -le $before) { throw 'DLT no avanzo. Revisar logs de Account.' }
Write-Output "DLT particion 0: siguiente offset $before -> $after. Hay un nuevo registro; comprobar su ID con el consumidor administrativo de EC2."
Write-Output "En EC2, desde ~/kafka:"
Write-Output "docker compose exec -T kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server 127.0.0.1:9092 --topic $dlt --partition 0 --offset $before --max-messages 1 --timeout-ms 10000 --property print.key=true --property print.headers=true --property print.offset=true"
