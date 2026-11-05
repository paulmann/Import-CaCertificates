@{
    RootModule           = 'Import-CaCertificates.psm1'
    ModuleVersion        = '2.0.1'
    GUID                 = 'b6f2c1d9-3f5e-4c8a-9a1e-7d1c2b3a4f60'
    Author               = 'Mikhail Deynekin'
    CompanyName          = 'Mikhail Deynekin'
    Copyright            = '(c) 2025 Mikhail Deynekin. All rights reserved.'
    Description          = 'Imports public CA certificates into Windows certificate stores with explicit SHA-256 fingerprint verification, PEM/DER support, idempotent store handling, and machine-readable reports.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @('Import-CaCertificate')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('Windows', 'Certificate', 'CA', 'PKI', 'RootCA', 'IntermediateCA', 'Security', 'Trust')
            LicenseUri   = 'https://github.com/paulmann/Import-CaCertificates/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/paulmann/Import-CaCertificates'
            ReleaseNotes = '2.0.1: relicensed under the MIT License. 2.0.0 introduced the module with Import-CaCertificate, mandatory SHA-256 fingerprint verification for Root CA imports, multi-certificate PEM, chain validation, -Json/-PassThru reports, Pester tests and the PSScriptAnalyzer gate.'
        }
    }
}
