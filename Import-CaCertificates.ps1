#Requires -Version 7.5
#Requires -RunAsAdministrator

using namespace System.Security.Cryptography.X509Certificates
using namespace System.IO
using namespace System.Security.Principal

<#
.SYNOPSIS
    Imports public CA root and intermediate certificates into the Local Machine certificate store.

.DESCRIPTION
    This script downloads X.509 certificates from specified HTTPS URLs, parses them (supporting both PEM and DER formats),
    and imports them into the appropriate Windows Certificate Stores (Root or Intermediate Certification Authorities).
    
    It performs administrative checks, ensures secure downloads (HTTPS only), and manages temporary files securely.
    Designed for automation and production environments running PowerShell 7.5 or higher.

.PARAMETER RootUrl
    The HTTPS URL pointing to the Root CA certificate file (PEM or DER).

.PARAMETER IntermediateUrl
    (Optional) The HTTPS URL pointing to the Intermediate CA certificate file (PEM or DER).

.PARAMETER TempPath
    The directory path used for temporary storage during download and processing.
    Defaults to a unique subdirectory within the system TEMP folder.

.PARAMETER Force
    If specified, allows overwriting existing certificates in the store that have the same thumbprint.
    By default, existing certificates are skipped to maintain idempotency.

.PARAMETER KeepTempFiles
    If specified, temporary downloaded files will not be deleted after script execution.
    Useful for debugging or auditing. By default, temp files are cleaned up.

.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs. The cmdlet is not run.

.PARAMETER Confirm
    Prompts you for confirmation before running the cmdlet.

.EXAMPLE
    .\Import-CaCertificates.ps1 -RootUrl 'https://letsencrypt.org/certs/isrgrootx1.pem'
    
    Imports only the Root CA from Let's Encrypt.

.EXAMPLE
    .\Import-CaCertificates.ps1 -RootUrl 'https://example.com/root.cer' -IntermediateUrl 'https://example.com/inter.cer' -Verbose
    
    Imports Root and Intermediate certificates with verbose output enabled.

.EXAMPLE
    .\Import-CaCertificates.ps1 -RootUrl 'https://example.com/root.pem' -Force -KeepTempFiles
    
    Forces re-import of the certificate even if it exists and keeps temporary files for inspection.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. The script writes status information to the Information and Verbose streams.

.NOTES
    - Administrative privileges are required to write to the LocalMachine certificate store.
    - Only HTTPS URLs are allowed to prevent Man-in-the-Middle attacks during download.
    - Supports both PEM (Base64) and DER (Binary) certificate formats.
    - Tested on Windows 10/11 and Windows Server 2019/2022 with PowerShell 7.5+.
    - Author: Mikhail Deynekin (mid1977@gmail.com, https://deynekin.com)
    - License: MIT

.LINK
    https://github.com/mid1977/PowerShell-Tools
    https://docs.microsoft.com/en-us/powershell/module/pki/
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RootUrl,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$IntermediateUrl,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TempPath = (Join-Path -Path $env:TEMP -ChildPath "CaImport_$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"),

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$KeepTempFiles
)

#region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Unified logging function using Write-Information and Write-Verbose.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Verbose')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Error'   { Write-Error $formattedMessage }
        'Warning' { Write-Warning $formattedMessage }
        'Verbose' { Write-Verbose $formattedMessage }
        'Info'    { Write-Information -MessageData $formattedMessage -InformationAction Continue }
    }
}

function Test-Administrator {
    <#
    .SYNOPSIS
        Checks if the current user has administrative privileges.
    #>
    $identity = [WindowsIdentity]::GetCurrent()
    $principal = [WindowsPrincipal]::new($identity)
    return $principal.IsInRole([WindowsBuiltinRole]::Administrator)
}

function Invoke-SecureDownload {
    <#
    .SYNOPSIS
        Downloads a file from a secure HTTPS URL.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    # Enforce HTTPS
    if ($Url -notmatch '^https://') {
        throw "Security Violation: Only HTTPS URLs are allowed. Provided: '$Url'"
    }

    Write-Log "Downloading from '$Url'..." -Level Verbose

    try {
        $params = @{
            Uri             = $Url
            OutFile         = $DestinationPath
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
            UserAgent       = 'PowerShell-CaImporter/2.0 (Windows NT)'
            ProgressAction  = 'SilentlyContinue'
        }
        
        Invoke-WebRequest @params
    }
    catch {
        throw "Failed to download certificate from '$Url': $($_.Exception.Message)"
    }
}

function Get-CertificateObject {
    <#
    .SYNOPSIS
        Loads a certificate file into an X509Certificate2 object, handling PEM conversion.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    Write-Log "Loading certificate from '$FilePath'..." -Level Verbose
    $cert = $null

    try {
        # Attempt direct load (DER format)
        $cert = [X509Certificate2]::new($FilePath)
    }
    catch {
        # Fallback: Attempt PEM parsing
        Write-Log "Direct load failed, attempting PEM parsing..." -Level Verbose
        try {
            $content = [File]::ReadAllText($FilePath)
            
            if ($content -match '-----BEGIN CERTIFICATE-----') {
                # Extract Base64 content
                $base64 = $content -replace '-----BEGIN CERTIFICATE-----', '' `
                                      -replace '-----END CERTIFICATE-----', '' `
                                      -replace '\s', ''
                
                $derBytes = [Convert]::FromBase64String($base64)
                
                # Create cert from bytes
                $cert = [X509Certificate2]::new($derBytes)
            }
            else {
                throw "File content is neither valid DER nor PEM format."
            }
        }
        catch {
            throw "Failed to parse certificate file '$FilePath': $($_.Exception.Message)"
        }
    }

    if ($null -eq $cert) {
        throw "Certificate object is null after loading '$FilePath'."
    }

    Write-Log "Loaded Certificate: Subject='$($cert.Subject)', Thumbprint='$($cert.Thumbprint)'" -Level Info
    return $cert
}

function Import-CertToStore {
    <#
    .SYNOPSIS
        Imports a certificate into the LocalMachine store with duplicate checking.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [X509Certificate2]$Certificate,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Root', 'CA')]
        [string]$StoreName,

        [Parameter()]
        [switch]$Force
    )

    $store = $null
    try {
        $store = [X509Store]::new($StoreName, [StoreLocation]::LocalMachine)
        $store.Open([OpenFlags]::ReadWrite)

        # Check for existing certificate
        $existing = $store.Certificates.Find([X509FindType]::FindByThumbprint, $Certificate.Thumbprint, $false)

        if ($existing.Count -gt 0) {
            if ($Force) {
                Write-Log "Certificate exists. Force specified. Re-importing to '$StoreName'." -Level Warning
                # Remove old certificate before adding new one to avoid duplicates
                $store.Remove($existing[0])
            }
            else {
                Write-Log "Certificate already exists in '$StoreName' (Thumbprint: $($Certificate.Thumbprint)). Skipping." -Level Info
                return
            }
        }

        if ($PSCmdlet.ShouldProcess("LocalMachine\$StoreName", "Import certificate $($Certificate.Subject)")) {
            $store.Add($Certificate)
            Write-Log "Successfully imported certificate into 'LocalMachine\$StoreName'." -Level Info
        }
    }
    finally {
        if ($null -ne $store) {
            $store.Close()
            $store.Dispose()
        }
    }
}

#endregion Helper Functions

#region Main Execution

try {
    # 1. Prerequisite Checks
    if (-not (Test-Administrator)) {
        Write-Log "This script requires Administrative privileges. Please run as Administrator." -Level Error
        exit 1
    }

    Write-Log "Starting Certificate Import Process..." -Level Info
    Write-Log "Temporary Directory: $TempPath" -Level Verbose

    # 2. Prepare Temp Directory
    if (-not (Test-Path -Path $TempPath)) {
        $null = New-Item -Path $TempPath -ItemType Directory -Force -ErrorAction Stop
    }

    # 3. Process Root Certificate
    $rootCert = $null
    try {
        $rootFile = Join-Path -Path $TempPath -ChildPath 'root_cert.tmp'
        Invoke-SecureDownload -Url $RootUrl -DestinationPath $rootFile
        $rootCert = Get-CertificateObject -FilePath $rootFile
        Import-CertToStore -Certificate $rootCert -StoreName 'Root' -Force:$Force
    }
    finally {
        if ($null -ne $rootCert) { $rootCert.Dispose() }
    }

    # 4. Process Intermediate Certificate (Optional)
    if (-not [string]::IsNullOrWhiteSpace($IntermediateUrl)) {
        $intCert = $null
        try {
            $intFile = Join-Path -Path $TempPath -ChildPath 'intermediate_cert.tmp'
            Invoke-SecureDownload -Url $IntermediateUrl -DestinationPath $intFile
            $intCert = Get-CertificateObject -FilePath $intFile
            Import-CertToStore -Certificate $intCert -StoreName 'CA' -Force:$Force
        }
        finally {
            if ($null -ne $intCert) { $intCert.Dispose() }
        }
    }

    Write-Log "Certificate import process completed successfully." -Level Info
}
catch {
    Write-Log "Script terminated due to error: $($_.Exception.Message)" -Level Error
    exit 1
}
finally {
    # 5. Cleanup
    if (-not $KeepTempFiles) {
        if (Test-Path -Path $TempPath) {
            Write-Log "Cleaning up temporary directory: $TempPath" -Level Verbose
            Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Log "Temporary files retained at: $TempPath" -Level Warning
    }
}

#endregion Main Execution
