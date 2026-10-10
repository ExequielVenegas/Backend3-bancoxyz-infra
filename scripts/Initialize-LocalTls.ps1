#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$directory = Join-Path $root 'secrets/tls'
$certPath = Join-Path $directory 'localhost.crt'
$keyPath = Join-Path $directory 'localhost.key'
if ((Test-Path $certPath) -or (Test-Path $keyPath)) {
    if (-not ((Test-Path $certPath) -and (Test-Path $keyPath))) {
        throw 'TLS incompleto: restaurar el certificado y su clave. No se sobrescriben archivos existentes.'
    }
    $existing = [Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPemFile($certPath, $keyPath)
    try {
        if ($existing.NotAfter -le (Get-Date)) { throw 'Certificado TLS vencido. Renovar y volver a configurar la confianza del cliente.' }
    } finally { $existing.Dispose() }
    Write-Output 'Certificado TLS existente conservado.'
    return
}
New-Item -ItemType Directory -Force $directory | Out-Null
$rsa = [Security.Cryptography.RSA]::Create(3072)
try {
    $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=localhost', $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $san = [Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
    $san.AddDnsName('localhost')
    $san.AddIpAddress([Net.IPAddress]::Loopback)
    $san.AddIpAddress([Net.IPAddress]::IPv6Loopback)
    $request.CertificateExtensions.Add($san.Build())
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false,$false,0,$true))
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
        ([Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor
         [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment), $true))
    $oids = [Security.Cryptography.OidCollection]::new()
    $null = $oids.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1'))
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids,$true))
    $certificate = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5), [DateTimeOffset]::UtcNow.AddDays(365))
    try {
        [IO.File]::WriteAllText($certPath, $certificate.ExportCertificatePem())
        [IO.File]::WriteAllText($keyPath, $rsa.ExportPkcs8PrivateKeyPem())
        [IO.File]::WriteAllBytes((Join-Path $directory 'localhost.cer'), $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    } finally { $certificate.Dispose() }
} finally { $rsa.Dispose() }
Write-Output 'TLS generado para localhost, 127.0.0.1 y ::1. No se modifico el almacen de confianza de Windows.'
