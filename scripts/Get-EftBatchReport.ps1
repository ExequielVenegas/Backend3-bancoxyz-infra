#requires -Version 7.0
param([ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')][string]$Period='2026-10',
      [string]$MysqlPath='C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$content=[IO.File]::ReadAllText((Join-Path $root '.env'))
$info=[Diagnostics.ProcessStartInfo]::new($MysqlPath)
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.RedirectStandardInput=$true
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
$user=[regex]::Match($content,'(?m)^EFT_BATCH_DB_USERNAME=([^\r\n]*)').Groups[1].Value.Trim()
$info.Environment['MYSQL_PWD']=[regex]::Match($content,'(?m)^EFT_BATCH_DB_PASSWORD=([^\r\n]*)').Groups[1].Value.Trim()
foreach($arg in @('--no-defaults','--host=127.0.0.1',"--user=$user",'--database=bancoxyz_batch_eft','--table')) { $info.ArgumentList.Add($arg) }
$sql=@"
SELECT kind,source_hash,status,reason,COUNT(*) AS filas FROM eft_records
WHERE period='$Period' GROUP BY kind,source_hash,status,reason ORDER BY kind,status,reason;
SELECT kind,COUNT(*) filas,COUNT(DISTINCT worker) hilos FROM eft_records WHERE period='$Period' GROUP BY kind;
SELECT i.JOB_NAME,e.JOB_EXECUTION_ID,e.STATUS,e.START_TIME,e.END_TIME
FROM BATCH_JOB_INSTANCE i JOIN BATCH_JOB_EXECUTION e ON e.JOB_INSTANCE_ID=i.JOB_INSTANCE_ID
ORDER BY e.JOB_EXECUTION_ID;
"@
$process=[Diagnostics.Process]::Start($info)
$output=$process.StandardOutput.ReadToEndAsync(); $errors=$process.StandardError.ReadToEndAsync()
$process.StandardInput.WriteLine($sql); $process.StandardInput.Close(); $process.WaitForExit()
$result=$output.GetAwaiter().GetResult(); $errorText=$errors.GetAwaiter().GetResult(); $code=$process.ExitCode
$process.Dispose()
if($code -ne 0) { throw "No se pudo consultar el esquema EFT: $errorText" }
Write-Output $result
