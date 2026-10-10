#requires -Version 7.0
param([Parameter(Mandatory)][string]$ReviewFile,[switch]$Apply)
$ErrorActionPreference='Stop'
$review=Get-Content -LiteralPath $ReviewFile -Raw | ConvertFrom-Json
if($review.version -ne 1) { throw 'Version de revision no admitida.' }
$candidates=@(& "$PSScriptRoot/Get-EftAssociationCandidates.ps1" -Period $review.periodo)
$approved=@($review.decisiones | Where-Object { $_.revisado -is [bool] -and $_.revisado })
if($approved.Count -eq 0) { throw 'No hay decisiones revisadas. Elegir una fila y cliente existente de manera explicita.' }
if(@($approved | Group-Object legacyId | Where-Object Count -gt 1).Count -gt 0) { throw 'Hay mas de una decision aprobada para la misma cuenta legacy.' }
$bodies=@(foreach($d in $approved) {
    $source=@($candidates | Where-Object { $_.legacyId -eq $d.legacyId -and $_.archivoHash -ceq $d.archivoHash -and $_.linea -eq $d.linea })
    if($source.Count -ne 1 -or $d.periodo -cne $review.periodo) { throw "Fuente invalida para legacyId $($d.legacyId)." }
    if(-not $source[0].importable -or $d.tipoOrigen -cne 'ahorro') { throw 'Prestamos e hipotecas conservan su historial; no se convierten a ahorro.' }
    if([decimal]$d.saldoOriginal -ne $source[0].saldoOriginal) { throw 'El saldo no coincide con el original del ETL.' }
    $customer=[guid]::Empty
    if(-not [guid]::TryParse([string]$d.clienteId,[ref]$customer) -or $customer -eq [guid]::Empty) { throw 'Indicar un clienteId UUID existente.' }
    if([string]::IsNullOrWhiteSpace($d.motivo) -or $d.motivo.Trim().Length -lt 10 -or $d.motivo.Length -gt 500) { throw 'Documentar el motivo de la seleccion (10 a 500 caracteres).' }
    if([string]::IsNullOrWhiteSpace($d.alias) -or $d.alias.Length -gt 80) { throw 'Alias requerido, maximo 80 caracteres.' }
    [ordered]@{legacyId=[int]$d.legacyId;clienteId=$customer.ToString();archivoHash=$d.archivoHash;linea=[int]$d.linea;periodo=$d.periodo;tipoOrigen='ahorro';saldoOriginal=[decimal]::Parse($source[0].saldoOriginal,[Globalization.CultureInfo]::InvariantCulture);alias=$d.alias.Trim();motivo=$d.motivo.Trim();revisado=$true}
})
Write-Output "Decisiones validadas contra el ETL: $($bodies.Count)."
if(-not $Apply) { Write-Output 'Solo validacion. Usar -Apply para enviar estas decisiones al BFF Web.'; return }
$token=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.accounts.import'
$issued=Get-Date
try {
    foreach($body in $bodies) {
        if(((Get-Date)-$issued).TotalSeconds -gt 150) {
            $token=& "$PSScriptRoot/Get-WebToken.ps1" -Scope 'web.accounts.import'
            $issued=Get-Date
        }
        $response=& "$PSScriptRoot/Invoke-LocalHttps.ps1" -Uri 'https://localhost:8081/api/web/cuentas-modernas/importaciones' -Method POST -Headers @{Authorization="Bearer $token"} -JsonBody ($body | ConvertTo-Json -Compress)
        if($response.StatusCode -ne 201) { throw "Asociacion legacy $($body.legacyId): HTTP $($response.StatusCode). Consultar el resultado antes de cambiar decisiones; se puede repetir el mismo archivo." }
        $account=$response.Content | ConvertFrom-Json
        Write-Output "Legacy $($body.legacyId) -> cuenta $($account.cuentaId); estado $($account.estado); saldo $($account.saldo)."
    }
} finally { Remove-Variable token -ErrorAction SilentlyContinue }


