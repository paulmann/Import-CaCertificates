#Requires -Version 7.4
<#
    Shared helpers for the Import-CaCertificates Pester test suite.
    Dot-source this file from a BeforeAll block.
#>

function New-TestCaCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommonName,

        [Parameter()]
        [string]$OutFile,

        [Parameter()]
        [DateTimeOffset]$NotBefore = [DateTimeOffset]::UtcNow.AddDays(-2),

        [Parameter()]
        [DateTimeOffset]$NotAfter = [DateTimeOffset]::UtcNow.AddYears(1),

        [Parameter()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Issuer
    )

    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        $CommonName,
        $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

    $request.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true, $false, 0, $true))
    $request.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign -bor
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::CrlSign, $true))

    if ($null -eq $Issuer) {
        $certificate = $request.CreateSelfSigned($NotBefore, $NotAfter)
    }
    else {
        $serial = [byte[]]::new(9)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($serial)
        $serial[0] = 1
        $certificate = $request.Create($Issuer, $NotBefore, $NotAfter, $serial)
    }

    if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
        [System.IO.File]::WriteAllText($OutFile, $certificate.ExportCertificatePem())
    }

    return $certificate
}

function New-TestLeafCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommonName,

        [Parameter(Mandatory)]
        [string]$OutFile
    )

    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        $CommonName,
        $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $certificate = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1), [DateTimeOffset]::UtcNow.AddDays(30))
    [System.IO.File]::WriteAllText($OutFile, $certificate.ExportCertificatePem())
    return $certificate
}

function Get-TestSha256 {
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Certificate.RawData))
}

function Get-TestStoreMatch {
    param(
        [Parameter(Mandatory)]
        [string]$Thumbprint,

        [Parameter()]
        [string]$StoreName = 'CA',

        [Parameter()]
        [string]$StoreLocation = 'CurrentUser'
    )

    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new($StoreName, $StoreLocation)
    try {
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
        return @($store.Certificates.Find(
                [System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
                $Thumbprint,
                $false))
    }
    finally {
        $store.Dispose()
    }
}

function Remove-TestStoreCertificate {
    param(
        [Parameter(Mandatory)]
        [string]$Thumbprint,

        [Parameter()]
        [string]$StoreName = 'CA',

        [Parameter()]
        [string]$StoreLocation = 'CurrentUser'
    )

    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new($StoreName, $StoreLocation)
    try {
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        foreach ($certificate in @($store.Certificates.Find(
                    [System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
                    $Thumbprint,
                    $false))) {
            $store.Remove($certificate)
        }
    }
    finally {
        $store.Dispose()
    }
}

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
