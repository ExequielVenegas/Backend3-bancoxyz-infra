#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$invoke = Join-Path $PSScriptRoot 'Invoke-LocalHttps.ps1'
foreach ($port in @(8081, 9000)) {
    $response = & $invoke -Uri "https://localhost:$port/actuator/health"
    if ($response.StatusCode -ne 200) { throw "Salud HTTPS incorrecta en $port" }
    $status = $null
    try { $status = (Invoke-WebRequest "http://localhost:$port/actuator/health" -TimeoutSec 5 -UseBasicParsing).StatusCode }
    catch { if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode } else { throw } }
    if ($status -ne 400) { throw "El puerto $port no rechazo HTTP plano como se esperaba" }
}
Write-Output 'OK: HTTPS con certificado valido y rechazo de HTTP plano.'

foreach ($port in @(8090, 8761)) {
    $socket = [Net.Sockets.TcpClient]::new()
    try {
        try { $null = $socket.ConnectAsync('127.0.0.1', $port).Wait(3000) } catch {}
        if ($socket.Connected) { throw "El puerto interno $port sigue accesible desde Windows" }
    } finally { $socket.Dispose() }
}
foreach ($path in @('/internal/accounts/137', '/eureka/apps', '/bff-web/cloud')) {
    if ((& $invoke -Uri "https://localhost:8081$path").StatusCode -ne 404) {
        throw "El proxy permite una ruta interna: $path"
    }
}
Write-Output 'OK: puertos internos cerrados y rutas de backend/plataforma no publicadas.'

$tempCert = Join-Path ([IO.Path]::GetTempPath()) ("bancoxyz-untrusted-" + [Guid]::NewGuid().ToString('N') + '.crt')
$rsa = [Security.Cryptography.RSA]::Create(2048)
try {
    $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=untrusted-test', $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $certificate = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-1), [DateTimeOffset]::UtcNow.AddDays(1))
    try { [IO.File]::WriteAllText($tempCert, $certificate.ExportCertificatePem()) }
    finally { $certificate.Dispose() }
    $rejected = $false
    try { $null = & $invoke -Uri 'https://localhost:8081/actuator/health' -CertificatePath $tempCert }
    catch {
        $exception = $_.Exception
        while ($exception) {
            if ($exception -is [Security.Authentication.AuthenticationException]) { $rejected = $true }
            $exception = $exception.InnerException
        }
        if (-not $rejected) { throw }
    }
    if (-not $rejected) { throw 'El cliente acepto un certificado sin confianza configurada' }
    Write-Output 'OK: TLS rechaza una confianza distinta al certificado del proyecto.'
} finally {
    $rsa.Dispose()
    if (Test-Path -LiteralPath $tempCert) { Remove-Item -LiteralPath $tempCert }
}
