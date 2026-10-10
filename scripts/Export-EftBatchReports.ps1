#requires -Version 7.0
param([Parameter(Mandatory)][ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')][string]$Period,
      [string]$MysqlPath='C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$content=[IO.File]::ReadAllText((Join-Path $root '.env'))
$destination=Join-Path $root "secrets/batch-reports/$Period"
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$queries=[ordered]@{
    'resumen-diario'=@"
SELECT source_hash,operation_date,operation_type,COUNT(*) registros,SUM(amount) monto_total
FROM eft_records WHERE kind='transactions' AND period='$Period' AND status='VALID'
GROUP BY source_hash,operation_date,operation_type ORDER BY source_hash,operation_date,operation_type;
"@
    'estado-anual'=@"
SELECT source_hash,reference_id,YEAR(operation_date) anio,operation_type,COUNT(*) registros,SUM(amount) monto_total
FROM eft_records WHERE kind='annual' AND period='$Period' AND status='VALID'
GROUP BY source_hash,reference_id,YEAR(operation_date),operation_type
ORDER BY source_hash,reference_id,anio,operation_type;
"@
    'intereses-mensuales'=@"
SELECT source_hash,source_line,period,rule_version,reference_id,operation_type,amount saldo_original,
interest interes_mensual,final_balance saldo_calculado,status,reason
FROM eft_records WHERE kind='interest' AND period='$Period' AND status<>'REJECTED'
ORDER BY source_hash,source_line;
"@
    'rechazos-y-pendientes'=@"
SELECT kind,source_hash,source_line,status,reason FROM eft_records
WHERE period='$Period' AND status<>'VALID' ORDER BY kind,source_hash,source_line;
"@
}
foreach($entry in $queries.GetEnumerator()) {
    $info=[Diagnostics.ProcessStartInfo]::new($MysqlPath)
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $user=[regex]::Match($content,'(?m)^EFT_BATCH_DB_USERNAME=([^\r\n]*)').Groups[1].Value.Trim()
    $info.Environment['MYSQL_PWD']=[regex]::Match($content,'(?m)^EFT_BATCH_DB_PASSWORD=([^\r\n]*)').Groups[1].Value.Trim()
    foreach($arg in @('--no-defaults','--host=127.0.0.1',"--user=$user",'--database=bancoxyz_batch_eft','--batch')) { $info.ArgumentList.Add($arg) }
    $process=[Diagnostics.Process]::Start($info)
    $output=$process.StandardOutput.ReadToEndAsync(); $errors=$process.StandardError.ReadToEndAsync()
    $process.StandardInput.WriteLine($entry.Value); $process.StandardInput.Close(); $process.WaitForExit()
    $result=$output.GetAwaiter().GetResult(); $errorText=$errors.GetAwaiter().GetResult(); $code=$process.ExitCode; $process.Dispose()
    if($code -ne 0) { throw "No se pudo exportar $($entry.Key): $errorText" }
    $file=Join-Path $destination "$($entry.Key).csv"
    $rows=@($result | ConvertFrom-Csv -Delimiter "`t")
    if($rows.Count -gt 0) { $rows | Export-Csv -LiteralPath $file -NoTypeInformation -Encoding utf8 }
    else { [IO.File]::WriteAllText($file,($result.TrimEnd() -replace "`t",',' )+[Environment]::NewLine) }
    Write-Output "$($entry.Key): $($rows.Count) filas; $file"
}
