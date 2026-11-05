<#
.SYNOPSIS
    Command-line wrapper for the Import-CaCertificates module: imports CA
    certificates into Windows certificate stores after explicit trust
    verification.

.DESCRIPTION
    This script is a thin CLI wrapper around Import-CaCertificate (module
    Import-CaCertificates). It accepts HTTPS URLs (-Uri), local files or
    directories (-Path), and the legacy -RootUrl/-IntermediateUrl parameters.

    Root CA imports require an expected SHA-256 fingerprint (-Thumbprint) unless
    -AllowUnverifiedRoot is passed. Importing a Root CA changes machine-wide
    trust; read docs/SECURITY-MODEL.md before using it on a production host.

.PARAMETER Uri
    One or more HTTPS URLs that return a certificate file (PEM, DER, or a
    multi-certificate PEM bundle).

.PARAMETER Path
    One or more certificate files, or directories containing .cer/.crt/.pem/.der
    files.

.PARAMETER RootUrl
    Deprecated. HTTPS URL of a Root CA certificate. Use -Uri instead.

.PARAMETER IntermediateUrl
    Deprecated. HTTPS URL of an Intermediate CA certificate. Use -Uri instead.

.PARAMETER Thumbprint
    Expected SHA-256 fingerprint(s), 64 hex characters. Spaces, colons and dashes
    are ignored. Every imported certificate must match one of these values.

.PARAMETER StoreLocation
    LocalMachine (default; requires an elevated session) or CurrentUser.

.PARAMETER StoreName
    Explicit target store: Root, CA, AuthRoot or TrustedPeople. By default a
    self-signed CA goes to Root and a non-self-signed CA goes to CA.

.PARAMETER NoRootImport
    Skip Root CA certificates instead of importing them.

.PARAMETER AllowUnverifiedRoot
    Permit a Root CA import without -Thumbprint. This is an explicit trust
    decision; the run is reported as unverified.

.PARAMETER RequireConfirmation
    Ask for an interactive yes/no confirmation before every store write.

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
    subdirectory is created and removed afterwards.

.PARAMETER SkipChainValidation
    Skip the signature-chain check between the roots and the intermediates in the
    same batch.

.PARAMETER WhatIf
    Show what would be imported without writing to the store.

.PARAMETER Confirm
    Prompt before importing each certificate. -Confirm:$false is required in
    non-interactive sessions.

.EXAMPLE
    .\Import-CaCertificates.ps1 -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' -Thumbprint 'CABD2A79A1076A31F21D253635CB039D4329A5E8C0B32E5915193B1C0A0B0B0B' -Confirm:$false

.EXAMPLE
    .\Import-CaCertificates.ps1 -Path 'C:\certs\root.pem' -WhatIf -Confirm:$false

.EXAMPLE
    .\Import-CaCertificates.ps1 -RootUrl 'https://example.com/root.cer' -IntermediateUrl 'https://example.com/inter.cer' -Thumbprint '<sha256-root>', '<sha256-intermediate>' -Confirm:$false

.NOTES
    Project: https://github.com/paulmann/Import-CaCertificates
    License: MIT (see LICENSE).
#>
#Requires -Version 7.4
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByUri')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ByUri', Position = 0)]
    [Alias('CertificateUri', 'Url')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Uri,

    [Parameter(Mandatory, ParameterSetName = 'ByPath', Position = 0)]
    [Alias('LiteralPath', 'FilePath')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Path,

    [Parameter(Mandatory, ParameterSetName = 'Legacy', Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$RootUrl,

    [Parameter(ParameterSetName = 'Legacy')]
    [string]$IntermediateUrl,

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
    [Alias('KeepFiles')]
    [switch]$KeepTempFiles,

    [Parameter()]
    [string]$TempPath,

    [Parameter()]
    [switch]$SkipChainValidation
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'src/Import-CaCertificates/Import-CaCertificates.psd1'

try {
    if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
        Import-Module -Name $modulePath -Force -ErrorAction Stop
    }
    elseif (Get-Module -ListAvailable -Name 'Import-CaCertificates') {
        Import-Module -Name 'Import-CaCertificates' -Force -ErrorAction Stop
    }
    else {
        throw "Import-CaCertificates module not found. Expected '$modulePath' or an installed copy of the module. Download a release archive instead of the single script."
    }
}
catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}

$invokeParameters = @{
    StoreLocation       = $StoreLocation
    NoRootImport        = $NoRootImport
    AllowUnverifiedRoot = $AllowUnverifiedRoot
    RequireConfirmation = $RequireConfirmation
    Force               = $Force
    PassThru            = $PassThru
    Json                = $Json
    LogLevel            = $LogLevel
    KeepTempFiles       = $KeepTempFiles
    SkipChainValidation = $SkipChainValidation
}

if ($null -ne $Thumbprint) {
    $invokeParameters['Thumbprint'] = $Thumbprint
}
if (-not [string]::IsNullOrWhiteSpace($StoreName)) {
    $invokeParameters['StoreName'] = $StoreName
}
if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
    $invokeParameters['LogFile'] = $LogFile
}
if (-not [string]::IsNullOrWhiteSpace($TempPath)) {
    $invokeParameters['TempPath'] = $TempPath
}

switch ($PSCmdlet.ParameterSetName) {
    'ByUri' {
        $invokeParameters['Uri'] = $Uri
    }
    'ByPath' {
        $invokeParameters['Path'] = $Path
    }
    'Legacy' {
        Write-Warning -Message 'The -RootUrl/-IntermediateUrl parameters are deprecated and will be removed in 3.0.0; use -Uri instead. Root CA imports now require -Thumbprint (SHA-256).'
        $legacyUris = @()
        if (-not [string]::IsNullOrWhiteSpace($RootUrl)) {
            $legacyUris += $RootUrl
        }
        if (-not [string]::IsNullOrWhiteSpace($IntermediateUrl)) {
            $legacyUris += $IntermediateUrl
        }
        $invokeParameters['Uri'] = $legacyUris
    }
}

if ($VerbosePreference -eq 'Continue') {
    $invokeParameters['Verbose'] = $true
}

try {
    Import-CaCertificate @invokeParameters
}
catch {
    $exitCode = 1
    if ($null -ne $_.Exception.Data -and $_.Exception.Data.Contains('CaExitCode')) {
        $exitCode = [int]$_.Exception.Data['CaExitCode']
    }
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit $exitCode
}
