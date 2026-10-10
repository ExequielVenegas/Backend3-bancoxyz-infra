#requires -Version 7.0
param([Parameter(Mandatory)][ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')][string]$Period,
      [string]$MysqlPath='C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$content=[IO.File]::ReadAllText((Join-Path $root '.env'))
$info=[Diagnostics.ProcessStartInfo]::new($MysqlPath)
$info.UseShellExecute=$false; $info.CreateNoWindow=$true
$info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
$user=[regex]::Match($content,'(?m)^EFT_BATCH_DB_USERNAME=([^\r\n]*)').Groups[1].Value.Trim()
$info.Environment['MYSQL_PWD']=[regex]::Match($content,'(?m)^EFT_BATCH_DB_PASSWORD=([^\r\n]*)').Groups[1].Value.Trim()
foreach($arg in @('--no-defaults','--host=127.0.0.1',"--user=$user",'--database=bancoxyz_batch_eft','--batch')) { $info.ArgumentList.Add($arg) }
$sql=@"
SELECT r.source_hash,r.source_line,r.reference_id,r.operation_type,r.amount,r.status,
REPLACE(TO_BASE64(r.raw_line),CHAR(10),'') raw_base64
FROM eft_records r WHERE r.kind='interest' AND r.period='$Period' AND r.rule_version='monthly-v1'
AND r.status IN ('VALID','PENDING_RECONCILIATION')
AND EXISTS (SELECT 1 FROM BATCH_JOB_INSTANCE i JOIN BATCH_JOB_EXECUTION e ON e.JOB_INSTANCE_ID=i.JOB_INSTANCE_ID
JOIN BATCH_JOB_EXECUTION_PARAMS h ON h.JOB_EXECUTION_ID=e.JOB_EXECUTION_ID AND h.PARAMETER_NAME='sha256' AND h.PARAMETER_VALUE=r.source_hash
JOIN BATCH_JOB_EXECUTION_PARAMS p ON p.JOB_EXECUTION_ID=e.JOB_EXECUTION_ID AND p.PARAMETER_NAME='period' AND p.PARAMETER_VALUE=r.period
JOIN BATCH_JOB_EXECUTION_PARAMS v ON v.JOB_EXECUTION_ID=e.JOB_EXECUTION_ID AND v.PARAMETER_NAME='rules' AND v.PARAMETER_VALUE=r.rule_version
WHERE i.JOB_NAME='eftInteresesMensualesJob' AND e.STATUS='COMPLETED')
ORDER BY r.reference_id,r.source_hash,r.source_line;
"@
$p=[Diagnostics.Process]::Start($info)
$o=$p.StandardOutput.ReadToEndAsync(); $e=$p.StandardError.ReadToEndAsync()
$p.StandardInput.WriteLine($sql); $p.StandardInput.Close(); $p.WaitForExit()
$result=$o.GetAwaiter().GetResult(); $errorText=$e.GetAwaiter().GetResult(); $code=$p.ExitCode; $p.Dispose()
if($code -ne 0) { throw "No se pudo leer el lote EFT: $errorText" }
foreach($r in @($result | ConvertFrom-Csv -Delimiter "`t")) {
    $raw=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($r.raw_base64))
    $source=$raw | ConvertFrom-Csv -Header cuenta_id,nombre,saldo,edad,tipo
    [pscustomobject][ordered]@{
        legacyId=[int]$r.reference_id; archivoHash=$r.source_hash; linea=[int]$r.source_line
        periodo=$Period; nombreOrigen=$source.nombre; tipoOrigen=$r.operation_type
        saldoOriginal=$r.amount
        estadoEtl=$r.status; importable=($r.operation_type -eq 'ahorro')
        clienteId=''; alias="Legacy EFT $($r.reference_id)"; motivo=''; revisado=$false
    }
}

