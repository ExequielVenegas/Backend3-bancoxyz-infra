#requires -Version 7.0
param(
    [Parameter(Mandatory = $true)][uri]$Uri,
    [ValidateSet('GET','POST','PUT')][string]$Method = 'GET',
    [hashtable]$Headers = @{},
    [hashtable]$Form = @{},
    [string]$JsonBody,
    [string]$CertificatePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'secrets/tls/localhost.crt')
)
$ErrorActionPreference = 'Stop'
if ($Uri.Scheme -ne 'https' -or -not $Uri.IsLoopback) {
    throw 'Este cliente esta limitado a HTTPS local.'
}
if (-not ('BancoXyz.LocalTls' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Net.Http;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
namespace BancoXyz {
    public static class LocalTls {
        public static HttpClient Create(string path) {
            var trusted = X509Certificate2.CreateFromPem(System.IO.File.ReadAllText(path));
            var handler = new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false, UseProxy = false };
            handler.ServerCertificateCustomValidationCallback = (request, certificate, chain, errors) => {
                if (certificate == null ||
                    (errors & (SslPolicyErrors.RemoteCertificateNameMismatch |
                               SslPolicyErrors.RemoteCertificateNotAvailable)) != 0) return false;
                using (var localChain = new X509Chain()) {
                    localChain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
                    localChain.ChainPolicy.CustomTrustStore.Add(trusted);
                    localChain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
                    localChain.ChainPolicy.VerificationFlags = X509VerificationFlags.NoFlag;
                    localChain.ChainPolicy.ApplicationPolicy.Add(new System.Security.Cryptography.Oid("1.3.6.1.5.5.7.3.1"));
                    return localChain.Build(certificate);
                }
            };
            return new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(10) };
        }
    }
}
'@
}
$client = [BancoXyz.LocalTls]::Create((Resolve-Path $CertificatePath).Path)
$request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
try {
    foreach ($key in $Headers.Keys) { $null = $request.Headers.TryAddWithoutValidation($key, [string]$Headers[$key]) }
    if ($PSBoundParameters.ContainsKey('JsonBody')) {
        $request.Content = [Net.Http.StringContent]::new($JsonBody, [Text.Encoding]::UTF8, 'application/json')
    } elseif ($Method -eq 'POST') {
        $values = [Collections.Generic.Dictionary[string,string]]::new()
        foreach ($key in $Form.Keys) { $values.Add($key, [string]$Form[$key]) }
        $request.Content = [Net.Http.FormUrlEncodedContent]::new($values)
    }
    $response = $client.SendAsync($request).GetAwaiter().GetResult()
    try {
        [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
    } finally { $response.Dispose() }
} finally { $request.Dispose(); $client.Dispose() }
