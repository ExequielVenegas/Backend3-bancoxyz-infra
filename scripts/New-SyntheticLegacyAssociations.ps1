#requires -Version 7.0
param([Parameter(Mandatory)][ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')][string]$Period)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$directory=Join-Path $root 'secrets/legacy-associations'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$path=Join-Path $directory "sintetica-$Period.json"
if(Test-Path -LiteralPath $path) {
    Write-Output "Se conserva la seleccion existente: $path"
    & "$PSScriptRoot/Invoke-LegacyAssociations.ps1" -ReviewFile $path
    return
}
$candidates=@(& "$PSScriptRoot/Get-EftAssociationCandidates.ps1" -Period $Period | Where-Object importable)
if($candidates.Count -eq 0) { throw 'No hay candidatos de ahorro.' }
if(@($candidates.archivoHash | Select-Object -Unique).Count -ne 1) {
    throw 'Hay varias versiones del archivo; no se elegira una implicitamente.'
}
# The selection is an explicitly synthetic convention, never an identity inference.
$selected=@($candidates | Group-Object legacyId | ForEach-Object {
    $_.Group | Sort-Object {[int]$_.linea} | Select-Object -First 1
} | Sort-Object {[int]$_.legacyId})
$token=$null; $issued=[datetime]::MinValue
try {
    foreach($d in $selected) {
        if(-not $token -or ((Get-Date)-$issued).TotalSeconds -gt 150) {
            $token=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.customers.write'
            $issued=Get-Date
        }
        $digest=[Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes("bancoxyz:eft:synthetic-customer:v1:$($d.legacyId)"))
        $key=[guid]::ParseExact([Convert]::ToHexString($digest).Substring(0,32),'N').ToString()
        $body=@{nombre="DEMO SINTETICO EFT - Legacy $($d.legacyId)";documento=$null;email=$null;telefono=$null;direccion=$null} | ConvertTo-Json -Compress
        $r=& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri 'https://localhost:8081/api/web/clientes' -Method POST -Headers @{Authorization="Bearer $token";'Idempotency-Key'=$key} -JsonBody $body
        if($r.StatusCode -ne 201) { throw "Cliente sintetico $($d.legacyId): HTTP $($r.StatusCode). Repetir este script conserva las claves de idempotencia." }
        $d.clienteId=($r.Content | ConvertFrom-Json).clienteId
        $d.alias="DEMO SINTETICA - Legacy $($d.legacyId)"
        $d.motivo='ASOCIACION SINTETICA autorizada para demostracion: primera fila de ahorro calculable por numero de linea. No confirma identidad legacy. Saldo original, sin sumar intereses ni movimientos.'
        $d.revisado=$true
        Write-Output "Cliente sintetico preparado para legacy $($d.legacyId)."
    }
} finally { Remove-Variable token -ErrorAction SilentlyContinue }
$review=[ordered]@{version=1;periodo=$Period;seleccion='SINTETICA_DEMO_V1';regla='Primera fila de ahorro calculable por linea, un cliente ficticio por legacyId; no es conciliacion real.';decisiones=$selected}
$review | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
& "$PSScriptRoot/Invoke-LegacyAssociations.ps1" -ReviewFile $path
Write-Output "Seleccion sintetica guardada: $path"
