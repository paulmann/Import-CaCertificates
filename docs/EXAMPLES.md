# Examples

All examples assume the module is available:

```powershell
Import-Module C:\Tools\Import-CaCertificates\src\Import-CaCertificates\Import-CaCertificates.psd1
```

Or, from the repository root, the CLI wrapper can be used directly:

```powershell
.\Import-CaCertificates.ps1 ...
```

Replace `<sha256-root>` / `<sha256-intermediate>` with the SHA-256 fingerprints you
obtained from the CA's published source. Fingerprints are 64 hex characters; spaces,
colons and dashes are ignored.

## 1. hMailServer (Windows)

hMailServer reports `Unknown CA` when the chain of an external TLS certificate is not
trusted by the Windows machine store.

```powershell
# Dry run first
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false

# Import
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false

# hMailServer caches its chain: restart the service afterwards
Restart-Service -Name hMailServer
```

If the server uses RSA intermediates from Let's Encrypt (R10/R11), the root above is
usually enough because Windows already ships the ISRG Root X1 or fetches it through
Automatic Root Update. If a private CA is used, import that CA's root and intermediate.

## 2. Exim on Windows

Exim reads the Windows machine store for `tls_verify_certificates` when configured to
use the system store. After the import, restart the Exim service (or reload its TLS
configuration) and test the chain with a TLS client such as `openssl s_client`.

Import the root and, when the server presents an intermediate that is not trusted yet:

```powershell
Import-CaCertificate -Path 'C:\certs\corp-root.pem' -Thumbprint '<sha256-root>' -Confirm:$false
Import-CaCertificate -Path 'C:\certs\corp-intermediate.pem' -Thumbprint '<sha256-intermediate>' -Confirm:$false
```

## 3. IIS / TLS on Windows Server

```powershell
Import-CaCertificate -Path 'C:\certs\corp-root.pem' -Thumbprint '<sha256-root>' `
    -StoreLocation LocalMachine -Confirm:$false
Restart-Service -Name W3SVC
```

For client certificates and specific trusted peers, use the `TrustedPeople` store
explicitly:

```powershell
Import-CaCertificate -Path 'C:\certs\partner-leaf.pem' -Thumbprint '<sha256-leaf>' `
    -StoreName TrustedPeople -Confirm:$false
```

## 4. Corporate PKI: root plus intermediates

```powershell
$thumbprints = @(
    '<sha256-root>'
    '<sha256-intermediate-1>'
    '<sha256-intermediate-2>'
)

# The bundle must contain exactly the certificates whose fingerprints are listed.
Import-CaCertificate -Path 'C:\certs\corp-chain.pem' `
    -Thumbprint $thumbprints -Confirm:$false -PassThru -LogFile 'C:\logs\pki-import.log'
```

`-NoRootImport` imports only the intermediates when the root is already trusted:

```powershell
Import-CaCertificate -Path 'C:\certs\corp-chain.pem' `
    -Thumbprint '<sha256-intermediate-1>' -NoRootImport -Confirm:$false
```

## 5. Offline / air-gapped host

On a connected machine:

```powershell
Invoke-WebRequest -Uri 'https://ca.example.com/root.cer' -OutFile '.\root.cer'
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('.\root.cer')
[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($cert.RawData))
```

Copy `root.cer` and the resulting fingerprint to the isolated host, then:

```powershell
Import-CaCertificate -Path 'D:\transfer\root.cer' -Thumbprint '<sha256-root>' -WhatIf -Confirm:$false
Import-CaCertificate -Path 'D:\transfer\root.cer' -Thumbprint '<sha256-root>' -Confirm:$false
```

## 6. Scheduled automation

```powershell
$log = 'C:\logs\ca-import-{0:yyyyMMdd}.log' -f (Get-Date)
$json = Import-CaCertificate -Uri 'https://ca.example.com/root.cer' `
    -Thumbprint '<sha256-root>' -Confirm:$false -Json -LogFile $log
$json | Out-File -LiteralPath 'C:\logs\ca-import.json' -Encoding utf8NoBOM

if ($LASTEXITCODE -ne 0) {
    # 0 = finished (check results), 1 = operational failure, 2 = security refusal
    Send-MailMessage -To 'pki@example.com' -Subject 'CA import failed' -Body $json
}
```

Inside a PowerShell script, `$LASTEXITCODE` is only set when the wrapper is started as a
child process (`pwsh -File`); when calling the module function directly, use `try/catch`
and inspect `$_.Exception.Data['CaExitCode']`.

## 7. Rollback

```powershell
# The result object reports the SHA-1 thumbprint used by certmgr.msc and certutil
$result = Import-CaCertificate -Path 'C:\certs\corp-root.pem' -Thumbprint '<sha256-root>' -Confirm:$false -PassThru
$result | Format-List Subject, ThumbprintSha1, ThumbprintSha256, Status

Remove-Item -Path "Cert:\LocalMachine\Root\$($result.ThumbprintSha1)"
```

`-Force` removes the existing certificate with the same SHA-256 fingerprint before
adding the downloaded one; if that certificate existed before the run, rollback means
importing it again from a trusted copy.
