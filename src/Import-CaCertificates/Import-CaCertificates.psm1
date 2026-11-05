#Requires -Version 7.4
<#
.SYNOPSIS
    Imports public CA certificates into Windows certificate stores with explicit
    fingerprint verification.

.DESCRIPTION
    The module provides a single public command, Import-CaCertificate, which reads
    certificates from HTTPS URLs or local files (PEM, DER, multi-certificate PEM),
    validates them as CA certificates, optionally verifies the chain against the
    roots in the same batch, and imports them into a Windows certificate store
    (LocalMachine or CurrentUser, Root or CA or AuthRoot or TrustedPeople).

    Importing a Root CA changes machine-wide trust. The command therefore requires
    an expected SHA-256 fingerprint for every imported certificate. The only way
    to import a root certificate without a fingerprint is the explicit
    -AllowUnverifiedRoot switch, which logs a warning.

    The command supports -WhatIf/-Confirm through ShouldProcess, -PassThru for
    structured result objects and -Json for a machine-readable envelope.

.NOTES
    License: MIT (see LICENSE).
    Project: https://github.com/paulmann/Import-CaCertificates
#>

Set-StrictMode -Version Latest

$script:ModuleVersion = '2.0.1'
$script:CaLogFile = $null
$script:CaLogLevel = 'Info'
$script:CaVerbose = $false

$script:CaLogRanks = @{
    None    = 0
    Error   = 1
    Warning = 2
    Info    = 3
    Verbose = 4
}

#region Private helpers

function Write-CaLog {
    <#
    .SYNOPSIS
        Writes one structured log line to the console and, optionally, to a log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Error', 'Warning', 'Info', 'Verbose')]
        [string]$Level = 'Info'
    )

    $rank = $script:CaLogRanks[$Level]
    $configured = $script:CaLogRanks[$script:CaLogLevel]

    if ($rank -gt $configured) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Error' {
            # Callers throw after logging, so the error text is shown by the caller;
            # this branch only feeds the log file.
        }
        'Warning' {
            Write-Warning -Message $Message
        }
        'Info' {
            Write-Information -MessageData $line -InformationAction Continue
        }
        'Verbose' {
            if ($script:CaVerbose) {
                Write-Verbose -Message $Message -Verbose
            }
        }
    }

    if ($script:CaLogFile) {
        try {
            $encoding = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::AppendAllText($script:CaLogFile, $line + [Environment]::NewLine, $encoding)
        }
        catch {
            Write-Warning -Message "Could not append to log file '$script:CaLogFile': $($_.Exception.Message)"
        }
    }
}

function Get-CaExceptionObject {
    <#
    .SYNOPSIS
        Creates an exception carrying an exit code for the CLI wrapper.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateRange(1, 125)]
        [int]$ExitCode = 1
    )

    $exception = [System.InvalidOperationException]::new($Message)
    $exception.Data['CaExitCode'] = $ExitCode
    return $exception
}

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Returns $true when the current process runs with administrator rights on Windows.
    #>
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CertificateFingerprint {
    <#
    .SYNOPSIS
        Returns the SHA-256 fingerprint of a certificate as uppercase hex.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $hash = [System.Security.Cryptography.SHA256]::HashData($Certificate.RawData)
    return [Convert]::ToHexString($hash)
}

function ConvertTo-NormalizedThumbprint {
    <#
    .SYNOPSIS
        Normalizes a SHA-256 fingerprint supplied by the user and rejects other formats.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $clean = ($Value -replace '[\s:\-]', '').ToUpperInvariant()
    $clean = $clean -replace '^0X', ''

    if ($clean -match '^[0-9A-F]{64}$') {
        return $clean
    }

    if ($clean -match '^[0-9A-F]{40}$') {
        throw (Get-CaExceptionObject -Message "Invalid -Thumbprint value '$Value': it looks like a SHA-1 thumbprint (40 hex characters). This command requires the SHA-256 fingerprint (64 hex characters); compute it with Get-FileHash-like tooling or read the 'ThumbprintSha256' field from a previous run." -ExitCode 2)
    }

    throw (Get-CaExceptionObject -Message "Invalid -Thumbprint value '$Value': expected a SHA-256 fingerprint (64 hex characters). Spaces, colons and dashes are ignored." -ExitCode 2)
}

function Test-CertificateSelfSigned {
    <#
    .SYNOPSIS
        Heuristic self-signed check: the subject and issuer distinguished names are identical.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $subject = [Convert]::ToHexString($Certificate.SubjectName.RawData)
    $issuer = [Convert]::ToHexString($Certificate.IssuerName.RawData)
    return ($subject -eq $issuer)
}

function Test-CertificatePolicy {
    <#
    .SYNOPSIS
        Validates the structure and validity period of a certificate.
    .DESCRIPTION
        Returns structural errors (private key, expired, broken signature algorithm)
        and warnings (weak key, SHA-1, missing Basic Constraints). Store-specific
        eligibility (CA requirement, Key Usage) is checked by
        Assert-CertificateStoreEligibility once the target store is known.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $now = [DateTime]::UtcNow

    if ($Certificate.HasPrivateKey) {
        $errors.Add('the certificate contains a private key; public CA certificates never do. Export the public certificate only (Export-Certificate -Type CERT) and retry.')
    }

    if ($Certificate.NotBefore.ToUniversalTime() -gt $now.AddMinutes(5)) {
        $errors.Add("the certificate is not valid yet (NotBefore $($Certificate.NotBefore.ToString('u'))).")
    }

    if ($Certificate.NotAfter.ToUniversalTime() -lt $now.AddMinutes(-5)) {
        $errors.Add("the certificate is expired (NotAfter $($Certificate.NotAfter.ToString('u'))).")
    }

    $basicConstraints = $Certificate.Extensions |
        Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension] } |
        Select-Object -First 1

    $isCa = $false
    $hasBasicConstraints = $false
    $hasKeyCertSign = $false

    if ($null -eq $basicConstraints) {
        $warnings.Add('the certificate has no X.509 Basic Constraints extension; it cannot be used as a CA certificate.')
    }
    else {
        $hasBasicConstraints = $true
        $isCa = [bool]$basicConstraints.CertificateAuthority
    }

    $keyUsage = $Certificate.Extensions |
        Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension] } |
        Select-Object -First 1

    if ($null -ne $keyUsage) {
        $hasKeyCertSign = [bool]($keyUsage.KeyUsages -band [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign)
    }

    $signatureName = $Certificate.SignatureAlgorithm.FriendlyName
    if ($signatureName -match 'md5|md2') {
        $errors.Add("the certificate is signed with a broken algorithm ($signatureName).")
    }
    elseif ($signatureName -match 'sha1') {
        $warnings.Add("the certificate is signed with SHA-1 ($signatureName); many systems still accept it, but it should be replaced where possible.")
    }

    $publicKey = $Certificate.PublicKey
    if ($publicKey.Oid.Value -eq '1.2.840.113549.1.1.1') {
        $rsa = $publicKey.GetRSAPublicKey()
        if ($null -ne $rsa) {
            if ($rsa.KeySize -lt 2048) {
                $warnings.Add("the RSA key is only $($rsa.KeySize) bits; 2048 bits or more is recommended.")
            }
            $rsa.Dispose()
        }
    }
    elseif ($publicKey.Oid.Value -eq '1.2.840.10045.2.1') {
        $ecdsa = $publicKey.GetECDsaPublicKey()
        if ($null -ne $ecdsa) {
            if ($ecdsa.KeySize -lt 256) {
                $warnings.Add("the ECDSA key is only $($ecdsa.KeySize) bits; 256 bits or more is recommended.")
            }
            $ecdsa.Dispose()
        }
    }

    return [pscustomobject]@{
        Errors              = @($errors)
        Warnings            = @($warnings)
        IsCA                = $isCa
        HasBasicConstraints = $hasBasicConstraints
        HasKeyCertSign      = $hasKeyCertSign
        IsSelfSigned        = (Test-CertificateSelfSigned -Certificate $Certificate)
    }
}

function Assert-CertificateStoreEligibility {
    <#
    .SYNOPSIS
        Rejects a certificate that the selected store does not accept.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory)]
        [pscustomobject]$Policy,

        [Parameter(Mandatory)]
        [ValidateSet('Root', 'CA', 'AuthRoot', 'TrustedPeople')]
        [string]$StoreName
    )

    if ($StoreName -notin @('Root', 'CA', 'AuthRoot')) {
        return
    }

    if (-not $Policy.IsCA) {
        $message = if ($Policy.HasBasicConstraints) {
            "Certificate '$($Certificate.Subject)' is not a CA certificate (Basic Constraints CA=false); only CA certificates may be imported into the '$StoreName' store. Use -StoreName TrustedPeople for a non-CA certificate."
        }
        else {
            "Certificate '$($Certificate.Subject)' has no Basic Constraints extension, so its CA role cannot be established; it cannot be imported into the '$StoreName' store."
        }
        throw (Get-CaExceptionObject -Message $message -ExitCode 2)
    }

    if (-not $Policy.HasKeyCertSign) {
        $keyUsage = $Certificate.Extensions |
            Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension] } |
            Select-Object -First 1
        if ($null -ne $keyUsage) {
            throw (Get-CaExceptionObject -Message "Certificate '$($Certificate.Subject)' does not allow certificate signing (Key Usage lacks KeyCertSign); it cannot be imported into the '$StoreName' store." -ExitCode 2)
        }
        Write-Warning -Message "Certificate '$($Certificate.Subject)' has no Key Usage extension; the KeyCertSign capability is not stated explicitly."
    }
}

function Get-CertificateFromFile {
    <#
    .SYNOPSIS
        Parses a certificate file and returns all certificates it contains.
    .DESCRIPTION
        Supports PEM (one or more 'BEGIN CERTIFICATE' blocks), raw DER, and base64
        DER without PEM markers. PFX/P12 files are refused: they may contain a
        private key, and this tool imports public certificates only.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -in @('.pfx', '.p12')) {
        throw (Get-CaExceptionObject -Message "Refusing to import '$Path': PFX/P12 files may contain a private key. Export the public certificate with 'Export-Certificate -Type CERT' or 'certutil -ca.cert', then import that file." -ExitCode 2)
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) {
        throw (Get-CaExceptionObject -Message "Certificate file '$Path' is empty.")
    }

    $probeLength = [Math]::Min($bytes.Length, 4096)
    $probe = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $probeLength)

    if ($probe -match '-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----') {
        throw (Get-CaExceptionObject -Message "Refusing to import '$Path': the file contains a private key. Only public certificates are imported." -ExitCode 2)
    }

    $certificates = [System.Collections.Generic.List[System.Security.Cryptography.X509Certificates.X509Certificate2]]::new()
    $pemMatches = [regex]::Matches([System.Text.Encoding]::UTF8.GetString($bytes), '-----BEGIN CERTIFICATE-----(?<Body>[\s\S]*?)-----END CERTIFICATE-----')

    if ($pemMatches.Count -gt 0) {
        foreach ($match in $pemMatches) {
            $base64 = $match.Groups['Body'].Value -replace '\s', ''
            try {
                $der = [Convert]::FromBase64String($base64)
                $certificates.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($der))
            }
            catch {
                throw (Get-CaExceptionObject -Message "Failed to parse a PEM certificate block in '$Path': $($_.Exception.Message)" -ExitCode 2)
            }
        }
        return $certificates.ToArray()
    }

    if ($bytes[0] -eq 0x30) {
        try {
            $certificates.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes))
            return $certificates.ToArray()
        }
        catch {
            throw (Get-CaExceptionObject -Message "Failed to parse '$Path' as a DER certificate: $($_.Exception.Message). If this is a PFX/P12 file, export the public certificate first." -ExitCode 2)
        }
    }

    $text = [System.Text.Encoding]::UTF8.GetString($bytes).Trim()
    if ($text -match '^[A-Za-z0-9+/=\s]+$') {
        try {
            $der = [Convert]::FromBase64String(($text -replace '\s', ''))
            $certificates.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($der))
            return $certificates.ToArray()
        }
        catch {
            throw (Get-CaExceptionObject -Message "Failed to decode '$Path' as base64 DER: $($_.Exception.Message)" -ExitCode 2)
        }
    }

    throw (Get-CaExceptionObject -Message "Failed to parse '$Path': the file is neither PEM, DER nor base64 DER." -ExitCode 2)
}

function Invoke-CertificateDownload {
    <#
    .SYNOPSIS
        Downloads a certificate file from an HTTPS URL into the temporary directory.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref] $parsedUri)) {
        throw (Get-CaExceptionObject -Message "Invalid -Uri value '$Uri': an absolute URL is required." -ExitCode 2)
    }

    if ($parsedUri.Scheme -ne 'https') {
        throw (Get-CaExceptionObject -Message "Security violation: only https:// URLs are allowed, got '$($parsedUri.Scheme)://' in '$Uri'. Certificate downloads over plain HTTP can be replaced in transit." -ExitCode 2)
    }

    Write-CaLog -Message "Downloading '$($parsedUri.AbsoluteUri)'..." -Level Verbose

    $requestParameters = @{
        Uri                = $parsedUri.AbsoluteUri
        OutFile            = $DestinationPath
        UseBasicParsing    = $true
        ErrorAction        = 'Stop'
        TimeoutSec         = 60
        MaximumRedirection = 5
        UserAgent          = "Import-CaCertificates/$script:ModuleVersion (Windows; PowerShell)"
        ProgressAction     = 'SilentlyContinue'
    }

    try {
        Invoke-WebRequest @requestParameters
    }
    catch {
        throw (Get-CaExceptionObject -Message "Failed to download certificate from '$Uri': $($_.Exception.Message)")
    }

    $length = (Get-Item -LiteralPath $DestinationPath).Length
    if ($length -eq 0) {
        throw (Get-CaExceptionObject -Message "Download from '$Uri' produced an empty file.")
    }
    if ($length -gt 2MB) {
        throw (Get-CaExceptionObject -Message "Download from '$Uri' is larger than 2 MB ($length bytes); refusing to treat it as a certificate file.")
    }
}

function Test-CertificateChainSignature {
    <#
    .SYNOPSIS
        Builds a chain for a certificate using only the supplied roots as trust anchors.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2[]]$TrustedRoots
    )

    $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
    try {
        $chain.ChainPolicy.TrustMode = [System.Security.Cryptography.X509Certificates.X509ChainTrustMode]::CustomRootTrust
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        $chain.ChainPolicy.DisableCertificateDownloads = $true

        foreach ($root in $TrustedRoots) {
            $null = $chain.ChainPolicy.CustomTrustStore.Add($root)
        }

        $isValid = $chain.Build($Certificate)
        $statuses = @($chain.ChainStatus | ForEach-Object { "$($_.Status): $($_.StatusInformation.Trim())" })

        return [pscustomobject]@{
            IsValid  = $isValid
            Statuses = $statuses
        }
    }
    finally {
        $chain.Dispose()
    }
}

function Get-CertificateSourceFile {
    <#
    .SYNOPSIS
        Resolves a -Path value to one or more certificate files.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw (Get-CaExceptionObject -Message "Path '$Path' does not exist.")
    }

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath

    if (Test-Path -LiteralPath $resolved -PathType Container) {
        $supported = @('.cer', '.crt', '.pem', '.der', '.cert')
        $files = @(Get-ChildItem -LiteralPath $resolved -File | Where-Object { $_.Extension.ToLowerInvariant() -in $supported })
        if ($files.Count -eq 0) {
            throw (Get-CaExceptionObject -Message "Directory '$Path' contains no certificate files ($($supported -join ', ')).")
        }
        return $files.FullName
    }

    return $resolved
}

function Import-X509CertificateToStore {
    <#
    .SYNOPSIS
        Adds one certificate to a store, deduplicating by SHA-256 fingerprint.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory)]
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$StoreLocation,

        [Parameter(Mandatory)]
        [ValidateSet('Root', 'CA', 'AuthRoot', 'TrustedPeople')]
        [string]$StoreName,

        [Parameter()]
        [switch]$Force
    )

    $sha256 = Get-CertificateFingerprint -Certificate $Certificate 
    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new($StoreName, $StoreLocation)
    $replaced = $false

    try {
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)

        $existing = @($store.Certificates | Where-Object {
                (Get-CertificateFingerprint -Certificate $_ ) -eq $sha256
            })

        if ($existing.Count -gt 0) {
            if (-not $Force) {
                return [pscustomobject]@{
                    Status   = 'AlreadyPresent'
                    Replaced = $false
                    Message  = "Certificate already exists in '$StoreLocation\$StoreName' (SHA-256 $sha256); nothing to do. Use -Force to replace it."
                }
            }

            Write-CaLog -Message "Certificate exists in '$StoreLocation\$StoreName'. -Force specified: replacing it." -Level Warning
            foreach ($item in $existing) {
                $store.Remove($item)
            }
            $replaced = $true
        }

        $store.Add($Certificate)

        $verification = @($store.Certificates | Where-Object {
                (Get-CertificateFingerprint -Certificate $_ ) -eq $sha256
            })

        if ($verification.Count -eq 0) {
            throw (Get-CaExceptionObject -Message "Certificate was not found in '$StoreLocation\$StoreName' after the import; the store write did not take effect.")
        }

        if ($replaced) {
            return [pscustomobject]@{
                Status   = 'Replaced'
                Replaced = $true
                Message  = "Replaced an existing certificate in '$StoreLocation\$StoreName' (SHA-256 $sha256)."
            }
        }

        return [pscustomobject]@{
            Status   = 'Imported'
            Replaced = $false
            Message  = "Imported into '$StoreLocation\$StoreName' (SHA-256 $sha256)."
        }
    }
    finally {
        $store.Dispose()
    }
}

function Get-CertificateResult {
    <#
    .SYNOPSIS
        Builds one result object for the report.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceType,

        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory)]
        [string]$StoreLocation,

        [Parameter(Mandatory)]
        [string]$StoreName,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter()]
        [string]$Reason = '',

        [Parameter()]
        [bool]$IsCA = $true,

        [Parameter()]
        [switch]$IsSelfSigned
    )

    return [pscustomobject]@{
        Timestamp      = (Get-Date).ToString('o')
        SourceType     = $SourceType
        Source         = $Source
        Subject        = $Certificate.Subject
        Issuer         = $Certificate.Issuer
        SerialNumber   = $Certificate.SerialNumber
        ThumbprintSha1 = $Certificate.Thumbprint
        ThumbprintSha256 = Get-CertificateFingerprint -Certificate $Certificate 
        NotBefore      = $Certificate.NotBefore.ToUniversalTime().ToString('o')
        NotAfter       = $Certificate.NotAfter.ToUniversalTime().ToString('o')
        IsCA           = $IsCA
        IsSelfSigned   = [bool]$IsSelfSigned
        StoreLocation  = $StoreLocation
        StoreName      = $StoreName
        Status         = $Status
        Reason         = $Reason
    }
}

#endregion Private helpers

function Import-CaCertificate {
    <#
    .SYNOPSIS
        Imports CA certificates into Windows certificate stores after explicit trust verification.

    .DESCRIPTION
        Reads certificates from HTTPS URLs (-Uri) or local files (-Path; PEM, DER,
        multi-certificate PEM, or a directory of certificate files), validates them
        as CA certificates, verifies that every imported certificate matches an
        expected SHA-256 fingerprint, and imports them into a Windows certificate
        store. Root CA imports additionally require a fingerprint unless
        -AllowUnverifiedRoot is passed.

        The command is idempotent: a certificate whose SHA-256 fingerprint is
        already present in the target store is skipped. -Force replaces an existing
        copy, but never skips fingerprint verification.

    .PARAMETER Uri
        One or more HTTPS URLs that return a certificate file.

    .PARAMETER Path
        One or more paths to certificate files, or directories containing files
        with the extensions .cer, .crt, .pem, .der or .cert.

    .PARAMETER Thumbprint
        Expected SHA-256 fingerprints (64 hex characters; spaces, colons and dashes
        are ignored). Every imported certificate must match one of these values.

    .PARAMETER StoreLocation
        LocalMachine (default; requires administrator rights) or CurrentUser.

    .PARAMETER StoreName
        Target store: Root (default for self-signed CA certificates), CA (default
        for intermediates), AuthRoot or TrustedPeople.

    .PARAMETER NoRootImport
        Skip Root CA certificates instead of importing them.

    .PARAMETER AllowUnverifiedRoot
        Permit a Root CA import without -Thumbprint. This is a deliberate trust
        decision; a warning is written and the run is reported as unverified.

    .PARAMETER RequireConfirmation
        Ask for an interactive yes/no confirmation for every certificate before the
        store write, regardless of -Confirm. Not usable in non-interactive sessions.

    .PARAMETER Force
        Replace a certificate that is already present (same SHA-256 fingerprint).

    .PARAMETER PassThru
        Return one result object per certificate.

    .PARAMETER Json
        Write a single JSON envelope (results and summary) to the pipeline.

    .PARAMETER LogLevel
        Console and log-file verbosity: None, Error, Warning, Info (default) or
        Verbose.

    .PARAMETER LogFile
        Append log lines to this file (UTF-8 without BOM).

    .PARAMETER KeepTempFiles
        Keep downloaded certificate files in the temporary directory.

    .PARAMETER TempPath
        Parent directory for the temporary download directory. A unique
        subdirectory is created and removed afterwards, so existing files are
        never deleted.

    .PARAMETER SkipChainValidation
        Skip the signature-chain check between the roots and the intermediates in
        the same batch.

    .EXAMPLE
        Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' -Thumbprint 'CABD2A79A1076A31F21D253635CB039D4329A5E8C0B32E5915193B1C0A0B0B0B' -Confirm:$false

        Imports the pinned Let's Encrypt root certificate.

    .EXAMPLE
        Import-CaCertificate -Path '.\root.pem', '.\intermediate.pem' -Thumbprint '<sha256-root>', '<sha256-intermediate>' -Confirm:$false -PassThru

        Imports a root/intermediate pair from local files and returns the result objects.

    .EXAMPLE
        Get-ChildItem '.\certs' | ForEach-Object { Import-CaCertificate -Path $_.FullName -WhatIf }

        Dry run: validates every certificate and reports what would happen.

    .OUTPUTS
        None by default; PSCustomObject[] with -PassThru; System.String with -Json.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByUri')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByUri', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('CertificateUri', 'Url')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Uri,

        [Parameter(Mandatory, ParameterSetName = 'ByPath', Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('LiteralPath', 'FilePath')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [Parameter()]
        [Alias('ExpectedThumbprint', 'Fingerprint', 'Sha256')]
        [string[]]$Thumbprint,

        [Parameter()]
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$StoreLocation = 'LocalMachine',

        [Parameter()]
        [ValidateSet('Root', 'CA', 'AuthRoot', 'TrustedPeople')]
        [string]$StoreName,

        [Parameter()]
        [switch]$NoRootImport,

        [Parameter()]
        [switch]$AllowUnverifiedRoot,

        [Parameter()]
        [switch]$RequireConfirmation,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [switch]$Json,

        [Parameter()]
        [ValidateSet('None', 'Error', 'Warning', 'Info', 'Verbose')]
        [string]$LogLevel = 'Info',

        [Parameter()]
        [string]$LogFile,

        [Parameter()]
        [switch]$KeepTempFiles,

        [Parameter()]
        [string]$TempPath,

        [Parameter()]
        [switch]$SkipChainValidation
    )

    begin {
        if (-not $IsWindows) {
            throw (Get-CaExceptionObject -Message 'Import-CaCertificate supports Windows only: it uses the Windows certificate stores and WindowsIdentity.' -ExitCode 2)
        }

        $sources = [System.Collections.Generic.List[object]]::new()

        $resolvedThumbprints = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $Thumbprint) {
            foreach ($value in $Thumbprint) {
                $resolvedThumbprints.Add((ConvertTo-NormalizedThumbprint -Value $value))
            }
        }

        $explicitStoreName = $PSBoundParameters.ContainsKey('StoreName')

        if ($StoreLocation -eq 'LocalMachine' -and -not (Test-IsAdministrator)) {
            throw (Get-CaExceptionObject -Message 'LocalMachine certificate stores require an elevated (administrator) session. Start PowerShell as Administrator, or use -StoreLocation CurrentUser.' -ExitCode 2)
        }

        if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
            $logDirectory = Split-Path -Path $LogFile -Parent
            if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
                throw (Get-CaExceptionObject -Message "Directory for -LogFile '$logDirectory' does not exist.")
            }
        }

        $previousLogFile = $script:CaLogFile
        $previousLogLevel = $script:CaLogLevel
        $previousVerbose = $script:CaVerbose

        # Keep stdout parseable for -Json consumers unless the caller explicitly
        # asked for a log level. Warnings and errors still reach their streams.
        $effectiveLogLevel = $LogLevel
        if ($Json -and -not $PSBoundParameters.ContainsKey('LogLevel')) {
            $effectiveLogLevel = 'Warning'
        }

        $script:CaLogFile = if ([string]::IsNullOrWhiteSpace($LogFile)) { $null } else { $LogFile }
        $script:CaLogLevel = $effectiveLogLevel
        $script:CaVerbose = $VerbosePreference -eq 'Continue'

        $tempDirectory = $null
        $tempDirectoryCreated = $false
        $parsedCertificates = [System.Collections.Generic.List[System.Security.Cryptography.X509Certificates.X509Certificate2]]::new()
        $results = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByUri') {
            foreach ($item in $Uri) {
                $sources.Add([pscustomobject]@{ Type = 'Uri'; Value = $item })
            }
        }
        else {
            foreach ($item in $Path) {
                foreach ($file in @(Get-CertificateSourceFile -Path $item)) {
                    $sources.Add([pscustomobject]@{ Type = 'File'; Value = $file })
                }
            }
        }
    }

    end {
        try {
            Write-CaLog -Message "Import-CaCertificate $script:ModuleVersion started: $($sources.Count) source(s), target $StoreLocation\$(if ($StoreName) { $StoreName } else { '<auto>' })." -Level Info
            Write-CaLog -Message "Expected SHA-256 fingerprint(s): $(if ($resolvedThumbprints.Count -gt 0) { $resolvedThumbprints -join ', ' } else { '<none>' })" -Level Verbose

            $tempRoot = if ([string]::IsNullOrWhiteSpace($TempPath)) { $env:TEMP } else { $TempPath }
            try {
                $null = [System.IO.Directory]::CreateDirectory($tempRoot)
            }
            catch {
                throw (Get-CaExceptionObject -Message "Could not create temporary directory '$tempRoot': $($_.Exception.Message)")
            }

            $tempDirectory = Join-Path -Path $tempRoot -ChildPath ("CaImport_{0}" -f [System.Guid]::NewGuid().ToString('N').Substring(0, 12))
            try {
                $null = [System.IO.Directory]::CreateDirectory($tempDirectory)
            }
            catch {
                throw (Get-CaExceptionObject -Message "Could not create temporary directory '$tempDirectory': $($_.Exception.Message)")
            }
            $tempDirectoryCreated = $true
            Write-CaLog -Message "Temporary directory: $tempDirectory" -Level Verbose

            foreach ($source in $sources) {
                $sourcePath = $source.Value

                if ($source.Type -eq 'Uri') {
                    $downloadName = 'download_{0}.cer' -f [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
                    $sourcePath = Join-Path -Path $tempDirectory -ChildPath $downloadName
                    Invoke-CertificateDownload -Uri $source.Value -DestinationPath $sourcePath
                }

                Write-CaLog -Message "Reading certificates from '$($source.Value)'..." -Level Info
                $certificates = @(Get-CertificateFromFile -Path $sourcePath)

                $roots = [System.Collections.Generic.List[System.Security.Cryptography.X509Certificates.X509Certificate2]]::new()
                $entries = [System.Collections.Generic.List[object]]::new()

                foreach ($certificate in $certificates) {
                    $parsedCertificates.Add($certificate)
                    $policy = Test-CertificatePolicy -Certificate $certificate
                    $entries.Add([pscustomobject]@{ Certificate = $certificate; Policy = $policy })
                    if ($policy.IsSelfSigned -and $policy.IsCA) {
                        $roots.Add($certificate)
                    }
                }

                foreach ($entry in $entries) {
                    $certificate = $entry.Certificate
                    $policy = $entry.Policy
                    $sha256 = Get-CertificateFingerprint -Certificate $certificate 
                    Write-CaLog -Message "Certificate: Subject='$($certificate.Subject)', Issuer='$($certificate.Issuer)', SHA-256=$sha256, NotAfter=$($certificate.NotAfter.ToString('u'))" -Level Info

                    foreach ($warning in $policy.Warnings) {
                        Write-CaLog -Message "Certificate '$($certificate.Subject)': $warning" -Level Warning
                    }

                    if ($policy.Errors.Count -gt 0) {
                        $message = "Certificate '$($certificate.Subject)' (SHA-256 $sha256) failed validation: $($policy.Errors -join ' ')"
                        Write-CaLog -Message $message -Level Error
                        throw (Get-CaExceptionObject -Message $message -ExitCode 2)
                    }

                    $isRoot = $policy.IsSelfSigned

                    if ($explicitStoreName) {
                        $targetStore = $StoreName
                        if ($targetStore -eq 'Root' -and -not $isRoot) {
                            Write-CaLog -Message "Certificate '$($certificate.Subject)' is not self-signed but -StoreName Root was requested explicitly." -Level Warning
                        }
                    }
                    elseif ($isRoot) {
                        $targetStore = 'Root'
                    }
                    elseif ($policy.IsCA) {
                        $targetStore = 'CA'
                    }
                    else {
                        $message = "Certificate '$($certificate.Subject)' is not a CA certificate and no -StoreName was given. Use -StoreName TrustedPeople for non-CA certificates."
                        Write-CaLog -Message $message -Level Error
                        throw (Get-CaExceptionObject -Message $message -ExitCode 2)
                    }

                    Assert-CertificateStoreEligibility -Certificate $certificate -Policy $policy -StoreName $targetStore

                    if ($targetStore -eq 'Root' -and $NoRootImport) {
                        if ($explicitStoreName) {
                            throw (Get-CaExceptionObject -Message '-StoreName Root conflicts with -NoRootImport: the Root store was requested explicitly, but root imports are disabled.' -ExitCode 2)
                        }
                        $results.Add((Get-CertificateResult -SourceType $source.Type -Source $source.Value -Certificate $certificate -StoreLocation $StoreLocation -StoreName 'Root' -Status 'Skipped' -Reason 'NoRootImport' -IsSelfSigned:$isRoot -IsCA:$policy.IsCA))
                        Write-CaLog -Message "Skipping Root CA '$($certificate.Subject)' because -NoRootImport is set." -Level Warning
                        continue
                    }

                    if ($resolvedThumbprints.Count -gt 0 -and $sha256 -notin $resolvedThumbprints) {
                        $message = "Certificate '$($certificate.Subject)' has SHA-256 fingerprint $sha256, which does not match any expected -Thumbprint value ($($resolvedThumbprints -join ', ')). Refusing to import."
                        Write-CaLog -Message $message -Level Error
                        throw (Get-CaExceptionObject -Message $message -ExitCode 2)
                    }

                    if ($targetStore -eq 'Root' -and $resolvedThumbprints.Count -eq 0) {
                        if (-not $AllowUnverifiedRoot) {
                            $message = "Root CA import of '$($certificate.Subject)' requires an expected SHA-256 fingerprint (-Thumbprint). Obtain it from the CA's published page and pass it; -AllowUnverifiedRoot is the explicit override (not recommended)."
                            Write-CaLog -Message $message -Level Error
                            throw (Get-CaExceptionObject -Message $message -ExitCode 2)
                        }
                        Write-CaLog -Message "Root CA '$($certificate.Subject)' is imported WITHOUT fingerprint verification (-AllowUnverifiedRoot). This is a trust decision for the whole machine." -Level Warning
                    }

                    if (-not $SkipChainValidation -and -not $isRoot -and $roots.Count -gt 0) {
                        $chain = Test-CertificateChainSignature -Certificate $certificate -TrustedRoots $roots.ToArray()
                        if (-not $chain.IsValid) {
                            $message = "Certificate '$($certificate.Subject)' does not chain to the supplied root certificate(s): $($chain.Statuses -join '; '). Refusing to import a mismatched chain."
                            Write-CaLog -Message $message -Level Error
                            throw (Get-CaExceptionObject -Message $message -ExitCode 2)
                        }
                        Write-CaLog -Message "Chain validation passed for '$($certificate.Subject)' against the supplied root(s)." -Level Verbose
                    }

                    if ($RequireConfirmation) {
                        $query = "Import certificate '$($certificate.Subject)' (SHA-256 $sha256) into '$StoreLocation\$targetStore'?"
                        if (-not $PSCmdlet.ShouldContinue($query, 'Confirm certificate import')) {
                            $results.Add((Get-CertificateResult -SourceType $source.Type -Source $source.Value -Certificate $certificate -StoreLocation $StoreLocation -StoreName $targetStore -Status 'Declined' -Reason 'User declined confirmation' -IsSelfSigned:$isRoot -IsCA:$policy.IsCA))
                            Write-CaLog -Message "User declined the import of '$($certificate.Subject)'." -Level Warning
                            continue
                        }
                    }

                    $action = "Import certificate '$($certificate.Subject)' (SHA-256 $sha256)"
                    $target = "$StoreLocation\$targetStore"

                    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
                        $results.Add((Get-CertificateResult -SourceType $source.Type -Source $source.Value -Certificate $certificate -StoreLocation $StoreLocation -StoreName $targetStore -Status 'WhatIf' -Reason 'WhatIf/ShouldProcess' -IsSelfSigned:$isRoot -IsCA:$policy.IsCA))
                        continue
                    }

                    $import = Import-X509CertificateToStore -Certificate $certificate -StoreLocation $StoreLocation -StoreName $targetStore -Force:$Force
                    $reason = if ($import.Replaced) { 'Replaced an existing copy of the same certificate' } elseif ($import.Status -eq 'AlreadyPresent') { 'Certificate with the same SHA-256 fingerprint already present' } else { '' }
                    $results.Add((Get-CertificateResult -SourceType $source.Type -Source $source.Value -Certificate $certificate -StoreLocation $StoreLocation -StoreName $targetStore -Status $import.Status -Reason $reason -IsSelfSigned:$isRoot -IsCA:$policy.IsCA))
                    Write-CaLog -Message $import.Message -Level Info
                }
            }

            $summary = [pscustomobject]@{
                Imported       = @($results | Where-Object Status -eq 'Imported').Count
                Replaced       = @($results | Where-Object Status -eq 'Replaced').Count
                AlreadyPresent = @($results | Where-Object Status -eq 'AlreadyPresent').Count
                Skipped        = @($results | Where-Object Status -eq 'Skipped').Count
                Declined       = @($results | Where-Object Status -eq 'Declined').Count
                WhatIf         = @($results | Where-Object Status -eq 'WhatIf').Count
                Total          = $results.Count
                UnverifiedRoot = [bool]$AllowUnverifiedRoot
            }

            Write-CaLog -Message ("Finished: total={0}, imported={1}, replaced={2}, alreadyPresent={3}, skipped={4}, declined={5}, whatIf={6}." -f $summary.Total, $summary.Imported, $summary.Replaced, $summary.AlreadyPresent, $summary.Skipped, $summary.Declined, $summary.WhatIf) -Level Info

            if ($Json) {
                $envelope = [pscustomobject]@{
                    Version = $script:ModuleVersion
                    Timestamp = (Get-Date).ToString('o')
                    Summary = $summary
                    Results = @($results)
                }
                Write-Output -InputObject ($envelope | ConvertTo-Json -Depth 8)
            }
            elseif ($PassThru) {
                Write-Output -InputObject @($results)
            }
        }
        finally {
            foreach ($certificate in $parsedCertificates) {
                $certificate.Dispose()
            }

            if ($tempDirectoryCreated -and -not $KeepTempFiles) {
                try {
                    [System.IO.Directory]::Delete($tempDirectory, $true)
                    Write-CaLog -Message "Removed temporary directory '$tempDirectory'." -Level Verbose
                }
                catch {
                    Write-Warning -Message "Could not remove temporary directory '$tempDirectory': $($_.Exception.Message)"
                }
            }
            elseif ($tempDirectoryCreated -and $KeepTempFiles) {
                Write-Warning -Message "Temporary files retained at: $tempDirectory"
            }

            $script:CaLogFile = $previousLogFile
            $script:CaLogLevel = $previousLogLevel
            $script:CaVerbose = $previousVerbose
        }
    }
}

Export-ModuleMember -Function Import-CaCertificate
