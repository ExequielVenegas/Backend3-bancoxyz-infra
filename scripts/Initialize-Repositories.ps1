#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([switch]$OnlyAvailable)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$repositories=Get-Content (Join-Path $root 'repositories.json') -Raw|ConvertFrom-Json
$missing=@($repositories|Where-Object { -not $_.url })
if($missing.Count -and -not $OnlyAvailable){
 throw "Completar las URL en repositories.json: $($missing.directory -join ', '). Para clonar solo los configurados, usar -OnlyAvailable."
}
foreach($repo in $repositories){
 if($repo.directory -notmatch '^[a-z][a-z0-9-]+$'){throw 'Nombre de carpeta no permitido.'}
 if(-not $repo.url){Write-Warning "URL pendiente: $($repo.directory)";continue}
 if($repo.url -notmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$'){throw "URL no permitida para $($repo.directory); usar HTTPS sin credenciales."}
 $destination=Join-Path $root $repo.directory
 if(Test-Path -LiteralPath $destination){Write-Output "Se conserva carpeta existente: $($repo.directory)";continue}
 if($PSCmdlet.ShouldProcess($destination,"Clonar $($repo.url)")){
  git clone -- $repo.url $destination
  if($LASTEXITCODE -ne 0){throw "No se pudo clonar $($repo.directory). Revisar acceso y conservar cualquier clon parcial para diagnostico."}
 }
}
