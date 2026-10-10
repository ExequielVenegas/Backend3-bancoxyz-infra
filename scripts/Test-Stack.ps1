param(
    [Parameter(Mandatory = $true)]
    [int]$CuentaId,
    [int]$TimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$compose = Join-Path (Split-Path $PSScriptRoot -Parent) 'compose.yaml'

function Read-InternalJson([string]$Service, [string]$Uri) {
    $json = docker compose -f $compose exec -T $Service curl -fsS -H 'Accept: application/json' $Uri
    if ($LASTEXITCODE -ne 0) { throw "Fallo la comprobacion interna de $Service" }
    return ($json | ConvertFrom-Json)
}

do {
    try {
        $token = & (Join-Path $PSScriptRoot 'Get-WebToken.ps1')
        $headers = @{ Authorization = "Bearer $token" }
        $registry = Read-InternalJson 'platform-service' 'http://localhost:8761/eureka/apps'
        foreach ($name in @('ACCOUNT-SERVICE', 'BFF-WEB')) {
            $app = @($registry.applications.application) | Where-Object name -EQ $name
            if (-not (@($app.instance) | Where-Object status -EQ 'UP')) {
                throw "Servicio pendiente en Eureka: $name"
            }
        }
        $webInfo = & (Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1') -Uri 'https://localhost:8081/actuator/info' -Headers $headers
        if ($webInfo.StatusCode -ne 200) { throw 'No se pudo consultar info de Web por HTTPS' }
        $accountInfo = Read-InternalJson 'account-service' 'http://localhost:8090/actuator/info'
        foreach ($info in @($accountInfo, ($webInfo.Content | ConvertFrom-Json))) {
            if ($info.configuration.source -ne 'config-server') {
                throw 'Un servicio no confirma configuracion centralizada'
            }
        }
        $account = Read-InternalJson 'account-service' "http://localhost:8090/internal/accounts/$CuentaId"
        $webResponse = & (Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1') -Uri "https://localhost:8081/api/web/cuentas/$CuentaId" -Headers $headers
        if ($webResponse.StatusCode -ne 200) { throw "Consulta Web: HTTP $($webResponse.StatusCode)" }
        $web = $webResponse.Content | ConvertFrom-Json
        if ($account.accountId -ne $CuentaId -or $web.cuentaId -ne $CuentaId -or
            $null -eq $account.availableBalance -or $null -eq $web.saldoFinal -or
            $account.availableBalance -ne $web.saldoFinal) {
            throw 'La cuenta o el saldo difieren entre Account Service y BFF Web'
        }
        Write-Output 'OK: HTTPS validado, OAuth2, Eureka, Config Server y consulta coherente con Account/MySQL.'
        exit 0
    } catch {
        $lastFailure = $_.Exception.Message
        if ((Get-Date) -ge $deadline) {
            throw "La verificacion no termino correctamente: $lastFailure"
        }
        Start-Sleep -Seconds 5
    }
} while ($true)
