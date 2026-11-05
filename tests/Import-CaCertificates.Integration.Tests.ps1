#Requires -Version 7.4
<#
    Integration tests for Import-CaCertificates.

    These tests are intentionally gated:
      * network tests run only when $env:CI is set (GitHub Actions);
      * LocalMachine store tests run only in CI on an elevated Windows runner;
      * the non-admin refusal test runs only when the session is NOT elevated.

    The unit suite (Import-CaCertificates.Unit.Tests.ps1) covers everything that can
    be tested without the network or administrator rights.
#>

$ErrorActionPreference = 'Stop'

# Gating flags are computed at discovery time because Pester evaluates It -Skip
# before BeforeAll runs. They are intentionally not touched in BeforeAll.
$script:IntegrationCi = -not [string]::IsNullOrWhiteSpace($env:CI)
$script:IntegrationAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

BeforeAll {
    $script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/Import-CaCertificates/Import-CaCertificates.psd1'

    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    Import-Module -Name $script:ModulePath -Force

    $script:testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("CaImportIntegration_{0}" -f [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -Path $script:testRoot -ItemType Directory -ErrorAction Stop

    $script:rootObject = New-TestCaCertificate -CommonName 'CN=RAGRAF Integration Root CA' -OutFile (Join-Path $script:testRoot 'root.pem')
    $script:rootPem = Join-Path $script:testRoot 'root.pem'
    $script:rootSha256 = Get-TestSha256 -Certificate $script:rootObject
}

AfterAll {
    Remove-Module -Name 'Import-CaCertificates' -Force -ErrorAction SilentlyContinue
    if ($script:testRoot) {
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'HTTPS download' {
    It 'imports a public root CA over HTTPS in a dry run' -Skip:(-not $script:IntegrationCi) {
        $uri = 'https://letsencrypt.org/certs/isrgrootx1.pem'
        $downloaded = Join-Path $script:testRoot 'isrgrootx1.pem'
        Invoke-WebRequest -Uri $uri -OutFile $downloaded -UseBasicParsing -TimeoutSec 60
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($downloaded)
        $sha256 = Get-TestSha256 -Certificate $certificate

        $result = Import-CaCertificate -Uri $uri -Thumbprint $sha256 -StoreLocation CurrentUser -WhatIf -Confirm:$false -PassThru
        $result[0].Status | Should -Be 'WhatIf'
        $result[0].ThumbprintSha256 | Should -Be $sha256
    }

    It 'refuses a plain HTTP URL before any download' {
        $threw = $false
        $message = ''
        try {
            Import-CaCertificate -Uri 'http://letsencrypt.org/certs/isrgrootx1.pem' -Thumbprint ('0' * 64) -StoreLocation CurrentUser -WhatIf -Confirm:$false
        }
        catch {
            $threw = $true
            $message = $_.Exception.Message
        }
        $threw | Should -BeTrue
        $message | Should -Match 'https'
    }
}

Describe 'LocalMachine store' {
    It 'imports and removes a root CA in LocalMachine\Root' -Skip:(-not ($script:IntegrationCi -and $script:IntegrationAdmin)) {
        $thumbprint = $script:rootObject.Thumbprint
        try {
            $result = Import-CaCertificate -Path $script:rootPem -Thumbprint $script:rootSha256 -StoreLocation LocalMachine -Confirm:$false -PassThru
            $result[0].Status | Should -Be 'Imported'
            $result[0].StoreLocation | Should -Be 'LocalMachine'
            @(Get-TestStoreMatch -Thumbprint $thumbprint -StoreName 'Root' -StoreLocation 'LocalMachine').Count | Should -Be 1
        }
        finally {
            Remove-TestStoreCertificate -Thumbprint $thumbprint -StoreName 'Root' -StoreLocation 'LocalMachine'
        }
        @(Get-TestStoreMatch -Thumbprint $thumbprint -StoreName 'Root' -StoreLocation 'LocalMachine').Count | Should -Be 0
    }

    It 'refuses LocalMachine writes without administrator rights' -Skip:($script:IntegrationAdmin) {
        $threw = $false
        $exitCode = 0
        try {
            Import-CaCertificate -Path $script:rootPem -Thumbprint $script:rootSha256 -StoreLocation LocalMachine -WhatIf -Confirm:$false
        }
        catch {
            $threw = $true
            $exitCode = $_.Exception.Data['CaExitCode']
        }
        $threw | Should -BeTrue
        $exitCode | Should -Be 2
    }
}

Describe 'Interactive confirmation' {
    It 'fails in a non-interactive session when -RequireConfirmation is set' {
        $threw = $false
        try {
            Import-CaCertificate -Path $script:rootPem -Thumbprint $script:rootSha256 -StoreLocation CurrentUser -RequireConfirmation -WhatIf -Confirm:$false
        }
        catch {
            $threw = $true
        }
        $threw | Should -BeTrue
    }
}
