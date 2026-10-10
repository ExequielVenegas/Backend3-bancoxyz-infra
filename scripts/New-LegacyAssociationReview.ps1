#requires -Version 7.0
param([Parameter(Mandatory)][ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')][string]$Period)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$directory=Join-Path $root 'secrets/legacy-associations'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$path=Join-Path $directory "revision-$Period.json"
if(Test-Path -LiteralPath $path) { throw "Ya existe $path. Se conserva tu revision; no se sobrescribe." }
$candidates=@(& "$PSScriptRoot/Get-EftAssociationCandidates.ps1" -Period $Period)
if($candidates.Count -eq 0) { throw 'No hay filas calculables de un lote de intereses COMPLETED.' }
$review=[ordered]@{version=1;periodo=$Period;instrucciones='Elegir como maximo una fila de ahorro por legacyId. Completar clienteId existente y motivo; poner revisado=true solo en las decisiones elegidas. No modificar fuente ni saldo. No unir titulares por nombre.';decisiones=$candidates}
$review | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
Write-Output "Revision creada: $path"
Write-Output "Candidatos: $($candidates.Count). Ahorro importable tras revision: $(@($candidates | Where-Object importable).Count). Ninguna asociacion aplicada."
