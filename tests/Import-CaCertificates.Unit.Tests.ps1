#Requires -Version 7.4
<#
    Unit and behavioral tests for the Import-CaCertificates module.

    The tests do not need administrator rights and do not touch the network.
    Store writes go to CurrentUser\CA and are removed afterwards.
#>

$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'src/Import-CaCertificates/Import-CaCertificates.psd1'
    $script:WrapperPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'Import-CaCertificates.ps1'

    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    Import-Module -Name $script:ModulePath -Force
    $script:module = Get-Module -Name 'Import-CaCertificates'

    $script:testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("CaImportTests_{0}" -f [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -Path $script:testRoot -ItemType Directory -ErrorAction Stop

    $script:rootObject = New-TestCaCertificate -CommonName 'CN=RAGRAF Test Root CA' -OutFile (Join-Path $script:testRoot 'root.pem')
    $script:intermediateObject = New-TestCaCertificate -CommonName 'CN=RAGRAF Test Intermediate CA' -Issuer $script:rootObject -OutFile (Join-Path $script:testRoot 'intermediate.pem')
    $script:leafObject = New-TestLeafCertificate -CommonName 'CN=leaf.test.invalid' -OutFile (Join-Path $script:testRoot 'leaf.pem')
    $script:expiredObject = New-TestCaCertificate -CommonName 'CN=RAGRAF Test Expired Root' -OutFile (Join-Path $script:testRoot 'expired.pem') -NotBefore ([DateTimeOffset]::UtcNow.AddDays(-30)) -NotAfter ([DateTimeOffset]::UtcNow.AddDays(-1))

    $script:rootPem = Join-Path $script:testRoot 'root.pem'
    $script:intermediatePem = Join-Path $script:testRoot 'intermediate.pem'
    $script:leafPem = Join-Path $script:testRoot 'leaf.pem'
    $script:expiredPem = Join-Path $script:testRoot 'expired.pem'
    $script:rootDer = Join-Path $script:testRoot 'root.der'
    $script:multiPem = Join-Path $script:testRoot 'bundle.pem'
    $script:mismatchPem = Join-Path $script:testRoot 'mismatch.pem'

    [System.IO.File]::WriteAllBytes($script:rootDer, $script:rootObject.RawData)
    [System.IO.File]::WriteAllText($script:multiPem, ($script:rootObject.ExportCertificatePem() + $script:intermediateObject.ExportCertificatePem()))
    $script:otherRootObject = New-TestCaCertificate -CommonName 'CN=RAGRAF Unrelated Root CA' -OutFile (Join-Path $script:testRoot 'other-root.pem')
    [System.IO.File]::WriteAllText($script:mismatchPem, ($script:otherRootObject.ExportCertificatePem() + $script:intermediateObject.ExportCertificatePem()))

    $script:rootSha256 = Get-TestSha256 -Certificate $script:rootObject
    $script:intermediateSha256 = Get-TestSha256 -Certificate $script:intermediateObject
    $script:leafSha256 = Get-TestSha256 -Certificate $script:leafObject
    $script:intermediateThumbprint = $script:intermediateObject.Thumbprint

    # Public-only views (no private key), as they arrive from a finished file.
    $script:rootPublic = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($script:rootPem)
    $script:leafPublic = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($script:leafPem)
}

AfterAll {
    Remove-Module -Name 'Import-CaCertificates' -Force -ErrorAction SilentlyContinue
    if ($script:testRoot) {
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Module surface' {
    It 'exports exactly the Import-CaCertificate function' {
        $exported = @($script:module.ExportedFunctions.Keys)
        $exported | Should -HaveCount 1
        $exported[0] | Should -Be 'Import-CaCertificate'
    }

    It 'reports version 2.0.1' {
        $script:module.Version.ToString() | Should -Be '2.0.1'
    }

    It 'exposes the documented parameters' {
        $command = Get-Command -Name Import-CaCertificate -Module 'Import-CaCertificates'
        foreach ($name in @('Uri', 'Path', 'Thumbprint', 'StoreLocation', 'StoreName', 'NoRootImport', 'AllowUnverifiedRoot', 'RequireConfirmation', 'Force', 'PassThru', 'Json', 'LogLevel', 'LogFile', 'KeepTempFiles', 'TempPath', 'SkipChainValidation')) {
            $command.Parameters.ContainsKey($name) | Should -BeTrue -Because "parameter '$name' is part of the public contract"
        }
    }

    It 'marks ShouldProcess as supported' {
        $attribute = (Get-Command -Name Import-CaCertificate -Module 'Import-CaCertificates').ScriptBlock.Attributes |
            Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] } |
            Select-Object -First 1
        $attribute.SupportsShouldProcess | Should -BeTrue
        $attribute.ConfirmImpact.ToString() | Should -Be 'High'
    }
}

Describe 'Thumbprint normalization' {
    It 'accepts a SHA-256 fingerprint with separators and returns uppercase hex' {
        $inputValue = ($script:rootSha256 -replace '(.{2})', '$1:')
        $result = & $script:module { param($value) ConvertTo-NormalizedThumbprint -Value $value } $inputValue
        $result | Should -Be $script:rootSha256
    }

    It 'rejects a SHA-1 length fingerprint with a helpful message' {
        $threw = $false
        $message = ''
        try { & $script:module { param($value) ConvertTo-NormalizedThumbprint -Value $value } 'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01' }
        catch { $threw = $true; $message = $_.Exception.Message }
        $threw | Should -BeTrue
        $message | Should -Match 'SHA-1'
    }

    It 'rejects a value with non-hex characters' {
        $threw = $false
        try { & $script:module { param($value) ConvertTo-NormalizedThumbprint -Value $value } ('ZZ' * 32) }
        catch { $threw = $true }
        $threw | Should -BeTrue
    }
}

Describe 'Certificate file parsing' {
    It 'parses a single PEM certificate' {
        $certificates = & $script:module { param($path) @(Get-CertificateFromFile -Path $path) } $script:rootPem
        @($certificates).Count | Should -Be 1
        $certificates[0].Subject | Should -Match 'Test Root CA'
    }

    It 'parses a DER certificate' {
        $certificates = & $script:module { param($path) @(Get-CertificateFromFile -Path $path) } $script:rootDer
        @($certificates).Count | Should -Be 1
        (Get-TestSha256 -Certificate $certificates[0]) | Should -Be $script:rootSha256
    }

    It 'parses a multi-certificate PEM bundle' {
        $certificates = & $script:module { param($path) @(Get-CertificateFromFile -Path $path) } $script:multiPem
        @($certificates).Count | Should -Be 2
    }

    It 'refuses a PEM file that contains a private key' {
        $path = Join-Path $script:testRoot 'with-key.pem'
        [System.IO.File]::WriteAllText($path, "-----BEGIN PRIVATE KEY-----`nAAAA`n-----END PRIVATE KEY-----`n" + [System.IO.File]::ReadAllText($script:rootPem))
        $threw = $false
        $message = ''
        try { & $script:module { param($p) Get-CertificateFromFile -Path $p } $path }
        catch { $threw = $true; $message = $_.Exception.Message }
        $threw | Should -BeTrue
        $message | Should -Match 'private key'
    }

    It 'refuses a PFX file by extension' {
        $path = Join-Path $script:testRoot 'dummy.pfx'
        [System.IO.File]::WriteAllBytes($path, [byte[]](1, 2, 3))
        $threw = $false
        try { & $script:module { param($p) Get-CertificateFromFile -Path $p } $path }
        catch { $threw = $true }
        $threw | Should -BeTrue
    }

    It 'refuses an empty file' {
        $path = Join-Path $script:testRoot 'empty.pem'
        [System.IO.File]::WriteAllBytes($path, [byte[]]@())
        $threw = $false
        try { & $script:module { param($p) Get-CertificateFromFile -Path $p } $path }
        catch { $threw = $true }
        $threw | Should -BeTrue
    }

    It 'expands a directory into certificate files' {
        $directory = Join-Path $script:testRoot 'directory'
        $null = New-Item -Path $directory -ItemType Directory -Force
        Copy-Item -LiteralPath $script:rootPem -Destination (Join-Path $directory 'a.pem')
        Copy-Item -LiteralPath $script:intermediatePem -Destination (Join-Path $directory 'b.cer')
        $files = & $script:module { param($p) @(Get-CertificateSourceFile -Path $p) } $directory
        @($files).Count | Should -Be 2
    }
}

Describe 'Certificate policy' {
    It 'accepts a CA certificate with keyCertSign' {
        $policy = & $script:module { param($c) Test-CertificatePolicy -Certificate $c } $script:rootPublic
        $policy.IsCA | Should -BeTrue
        $policy.HasKeyCertSign | Should -BeTrue
        @($policy.Errors).Count | Should -Be 0
    }

    It 'rejects an expired certificate' {
        $policy = & $script:module { param($c) Test-CertificatePolicy -Certificate $c } $script:expiredObject
        @($policy.Errors).Count | Should -BeGreaterThan 0
        ($policy.Errors -join ' ') | Should -Match 'expired'
    }

    It 'rejects a certificate that carries a private key' {
        $policy = & $script:module { param($c) Test-CertificatePolicy -Certificate $c } $script:rootObject
        ($policy.Errors -join ' ') | Should -Match 'private key'
    }

    It 'flags a leaf certificate without Basic Constraints as non-CA' {
        $policy = & $script:module { param($c) Test-CertificatePolicy -Certificate $c } $script:leafPublic
        $policy.IsCA | Should -BeFalse
        ($policy.Warnings -join ' ') | Should -Match 'Basic Constraints'
    }
}

Describe 'Import into CurrentUser\CA' {
    It 'imports an intermediate CA and returns a report object' {
        try {
            $result = Import-CaCertificate -Path $script:intermediatePem -Thumbprint $script:intermediateSha256 -StoreLocation CurrentUser -Confirm:$false -PassThru
            $result | Should -HaveCount 1
            $result[0].Status | Should -Be 'Imported'
            $result[0].StoreName | Should -Be 'CA'
            $result[0].ThumbprintSha256 | Should -Be $script:intermediateSha256
            $result[0].Subject | Should -Match 'Test Intermediate CA'
            @(Get-TestStoreMatch -Thumbprint $script:intermediateThumbprint).Count | Should -Be 1
        }
        finally {
            Remove-TestStoreCertificate -Thumbprint $script:intermediateThumbprint
        }
    }

    It 'is idempotent by SHA-256 fingerprint' {
        try {
            $null = Import-CaCertificate -Path $script:intermediatePem -Thumbprint $script:intermediateSha256 -StoreLocation CurrentUser -Confirm:$false
            $second = Import-CaCertificate -Path $script:intermediatePem -Thumbprint $script:intermediateSha256 -StoreLocation CurrentUser -Confirm:$false -PassThru
            $second[0].Status | Should -Be 'AlreadyPresent'
        }
        finally {
            Remove-TestStoreCertificate -Thumbprint $script:intermediateThumbprint
        }
    }

    It 'replaces the certificate with -Force' {
        try {
            $null = Import-CaCertificate -Path $script:intermediatePem -Thumbprint $script:intermediateSha256 -StoreLocation CurrentUser -Confirm:$false
            $result = Import-CaCertificate -Path $script:intermediatePem -Thumbprint $script:intermediateSha256 -StoreLocation CurrentUser -Confirm:$false -Force -PassThru
            $result[0].Status | Should -Be 'Replaced'
            @(Get-TestStoreMatch -Thumbprint $script:intermediateThumbprint).Count | Should -Be 1
        }
        finally {
            Remove-TestStoreCertificate -Thumbprint $script:intermediateThumbprint
        }
    }

    It 'honours -WhatIf without writing to the store' {
        $result = Import-CaCertificate -Path $script:rootPem -Thumbprint $script:rootSha256 -StoreLocation CurrentUser -WhatIf -Confirm:$false -PassThru
        $result[0].Status | Should -Be 'WhatIf'
        @(Get-TestStoreMatch -Thumbprint $script:rootObject.Thumbprint -StoreName 'Root').Count | Should -Be 0
    }

    It 'skips root certificates with -NoRootImport' {
        try {
            $results = Import-CaCertificate -Path $script:multiPem -Thumbprint $script:intermediateSha256 -NoRootImport -StoreLocation CurrentUser -Confirm:$false -PassThru
            @($results).Count | Should -Be 2
            ($results | Where-Object StoreName -eq 'Root').Status | Should -Be 'Skipped'
            ($results | Where-Object StoreName -eq 'CA').Status | Should -Be 'Imported'
        }
        finally {
            Remove-TestStoreCertificate -Thumbprint $script:intermediateThumbprint
        }
    }
}

Describe 'Trust verification' {
    It 'refuses a Root CA import without -Thumbprint' {
        $threw = $false
        $exitCode = 0
        try { Import-CaCertificate -Path $script:rootPem -StoreLocation CurrentUser -WhatIf -Confirm:$false }
        catch { $threw = $true; $exitCode = $_.Exception.Data['CaExitCode'] }
        $threw | Should -BeTrue
        $exitCode | Should -Be 2
    }

    It 'refuses a certificate whose fingerprint is not pinned' {
        $threw = $false
        $message = ''
        try { Import-CaCertificate -Path $script:intermediatePem -Thumbprint $script:rootSha256 -StoreLocation CurrentUser -WhatIf -Confirm:$false }
        catch { $threw = $true; $message = $_.Exception.Message }
        $threw | Should -BeTrue
        $message | Should -Match 'does not match'
    }

    It 'refuses a chain mismatch between supplied root and intermediate' {
        $threw = $false
        try { Import-CaCertificate -Path $script:mismatchPem -Thumbprint $script:intermediateSha256 -NoRootImport -StoreLocation CurrentUser -Confirm:$false }
        catch { $threw = $true }
        $threw | Should -BeTrue
    }

    It 'refuses an expired certificate' {
        $threw = $false
        try { Import-CaCertificate -Path $script:expiredPem -Thumbprint ('0' * 64) -StoreLocation CurrentUser -WhatIf -Confirm:$false }
        catch { $threw = $true }
        $threw | Should -BeTrue
    }

    It 'allows a non-CA certificate only when -StoreName TrustedPeople is explicit' {
        $result = Import-CaCertificate -Path $script:leafPem -Thumbprint $script:leafSha256 -StoreName TrustedPeople -StoreLocation CurrentUser -WhatIf -Confirm:$false -PassThru
        $result[0].Status | Should -Be 'WhatIf'
        $result[0].IsCA | Should -BeFalse
    }
}

Describe 'Machine-readable output and logging' {
    It 'writes a JSON envelope' {
        $json = Import-CaCertificate -Path $script:rootDer -Thumbprint $script:rootSha256 -StoreLocation CurrentUser -WhatIf -Confirm:$false -Json
        $envelope = $json | ConvertFrom-Json
        $envelope.Version | Should -Be '2.0.1'
        $envelope.Summary.Total | Should -Be 1
        $envelope.Results[0].Status | Should -Be 'WhatIf'
    }

    It 'appends log lines to -LogFile' {
        $logPath = Join-Path $script:testRoot 'import.log'
        $null = Import-CaCertificate -Path $script:rootPem -Thumbprint $script:rootSha256 -StoreLocation CurrentUser -WhatIf -Confirm:$false -LogFile $logPath
        Test-Path -LiteralPath $logPath | Should -BeTrue
        (Get-Content -LiteralPath $logPath -Raw) | Should -Match 'Import-CaCertificate 2\.0\.1 started'
    }
}

Describe 'CLI wrapper' {
    It 'returns exit code 0 for a dry run' {
        $output = & pwsh -NoProfile -File $script:WrapperPath -Path $script:rootPem -Thumbprint $script:rootSha256 -StoreLocation CurrentUser -WhatIf -Confirm:$false 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output | Out-String) | Should -Match 'Import-CaCertificate 2\.0\.1'
    }

    It 'returns exit code 2 when a Root CA has no pinned fingerprint' {
        $null = & pwsh -NoProfile -File $script:WrapperPath -Path $script:rootPem -StoreLocation CurrentUser -Confirm:$false 2>&1
        $LASTEXITCODE | Should -Be 2
    }

    It 'maps the deprecated -RootUrl parameter and warns' {
        $output = & pwsh -NoProfile -File $script:WrapperPath -RootUrl 'https://example.invalid/root.pem' -StoreLocation CurrentUser -WhatIf -Confirm:$false 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output | Out-String) | Should -Match 'deprecated'
    }
}
