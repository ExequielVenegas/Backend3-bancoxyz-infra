#requires -Version 7.0
param(
    [Parameter(Mandatory)][ValidateSet('transactions','interest','annual')][string]$Kind,
    [Parameter(Mandatory)][ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')][string]$Period,
    [string]$InputFile,
    [ValidateRange(1,8)][int]$Workers=3,
    [ValidateRange(1,3)][int]$Attempts=3,
    [string]$JavaPath='C:\Program Files\Java\jdk-25.0.4\bin\java.exe'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$batch=Join-Path $root 'legacy-batch-migrator'
$jar=Join-Path $batch 'target/legacy-batch-migrator-0.0.1-SNAPSHOT.jar'
if (-not (Test-Path -LiteralPath $jar)) { throw 'Compilar primero legacy-batch-migrator con mvnw.cmd package.' }
if (-not $InputFile) {
    $name=@{transactions='movimientos_financieros_diarios.csv';interest='intereses_trimestrales.csv';annual='estados_financieros_anuales.csv'}[$Kind]
    $InputFile=Join-Path $batch "src/main/resources/input/$name"
}
$InputFile=(Resolve-Path -LiteralPath $InputFile).Path
$hash=(Get-FileHash -LiteralPath $InputFile -Algorithm SHA256).Hash.ToLowerInvariant()
# Retain an immutable-by-convention copy for restart, excluded from Git.
$snapshots=Join-Path $root 'secrets/batch-input'
New-Item -ItemType Directory -Force -Path $snapshots | Out-Null
$snapshot=Join-Path $snapshots "$hash.csv"
if (-not (Test-Path -LiteralPath $snapshot)) { Copy-Item -LiteralPath $InputFile -Destination $snapshot }
if ((Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) {
    throw 'La copia de entrada cambio. No se reiniciara con datos diferentes.'
}
$envText=[IO.File]::ReadAllText((Join-Path $root '.env'))
$info=[Diagnostics.ProcessStartInfo]::new($JavaPath)
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
foreach ($key in @('EFT_BATCH_DB_URL','EFT_BATCH_DB_USERNAME','EFT_BATCH_DB_PASSWORD')) {
    $value=[regex]::Match($envText,"(?m)^$key=([^`r`n]*)").Groups[1].Value.Trim()
    if (-not $value) { throw "Falta $key. Ejecutar Initialize-EftBatchDatabase.ps1." }
    $info.Environment[$key]=$value
}
if ($info.Environment['EFT_BATCH_DB_URL'] -notmatch '^jdbc:mysql://(localhost|127\.0\.0\.1):3306/bancoxyz_batch_eft(\?.*)?$') {
    throw 'Este lanzador solo escribe en bancoxyz_batch_eft local; revisar EFT_BATCH_DB_URL.'
}
foreach ($arg in @('-jar',$jar,'--spring.profiles.active=eft','--eft.launch=true',
    "--eft.kind=$Kind","--eft.period=$Period","--eft.input=$snapshot","--eft.sha256=$hash",
    "--eft.workers=$Workers","--eft.attempts=$Attempts",
    "--bancoxyz.task-executor.core-pool-size=$Workers","--bancoxyz.task-executor.max-pool-size=$Workers")) {
    $info.ArgumentList.Add($arg)
}
Write-Output "EFT $Kind / periodo $Period / SHA256 $hash / workers $Workers"
$process=[Diagnostics.Process]::Start($info)
$output=$process.StandardOutput.ReadToEndAsync()
$errors=$process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$code=$process.ExitCode
$logPath=Join-Path $batch "eft-run-$Kind.log"
[IO.File]::WriteAllText($logPath,($output.GetAwaiter().GetResult()+$errors.GetAwaiter().GetResult()))
$process.Dispose()
if ($code -ne 0) { throw "El batch EFT fallo (codigo $code). Diagnostico: $logPath. Repetir el mismo comando permite reiniciar el lote; no cambiar periodo para eludir el fallo." }
Select-String -LiteralPath $logPath -Pattern 'EFT job=','already completed' | ForEach-Object { Write-Output $_.Line }
Write-Output 'Lote completado o ya procesado. Consultar eft_records para distinguir validos, rechazos y pendientes.'
