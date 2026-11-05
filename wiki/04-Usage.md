# Usage

This chapter is task-oriented. Every scenario shows the command, what it does, and the result to expect. All
examples assume the module is imported:

```powershell
Import-Module C:\Tools\Import-CaCertificates\src\Import-CaCertificates\Import-CaCertificates.psd1
```

From a repository checkout the wrapper can be used instead:
`.\Import-CaCertificates.ps1 <same parameters>`. Fingerprints are 64 hex characters; spaces, colons and
dashes are accepted and ignored. Replace `<sha256-root>` and `<sha256-intermediate>` with values obtained
from the CA's published source.

## Import a Root CA from a local file

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256-root>' `
    -StoreLocation LocalMachine -Confirm:$false -PassThru
```

A self-signed CA without `-StoreName` is routed to `LocalMachine\Root`. The result reports
`Status = Imported`, `StoreName = Root`. A repeat reports `AlreadyPresent`.

## Import an Intermediate CA only

```powershell
Import-CaCertificate -Path 'C:\certs\intermediate.pem' -Thumbprint '<sha256-intermediate>' -Confirm:$false
```

A non-self-signed CA is routed to `LocalMachine\CA` automatically. If the file contains a chain with no
root, chain validation is skipped (there is no supplied root to validate against) and the intermediate is
imported on its own.

## Import a multi-certificate bundle, skipping the root

```powershell
Import-CaCertificate -Path 'C:\certs\chain.pem' `
    -Thumbprint '<sha256-intermediate-1>', '<sha256-intermediate-2>' `
    -NoRootImport -Confirm:$false
```

Every certificate in the bundle is parsed and processed separately. `-NoRootImport` skips Root CA
certificates with status `Skipped` and imports the intermediates. The root is not written to the store, but
because it arrives in the same file it is still available as a trust anchor for the chain check of the
intermediates. That is the expected behaviour when the root is already trusted machine-wide and you are
refreshing only the intermediates.

## Import a directory of certificates

```powershell
Import-CaCertificate -Path 'C:\certs\corporate-cas' -Thumbprint '<sha256-1>', '<sha256-2>' `
    -WhatIf -Confirm:$false
```

A directory is expanded to files with the extensions `.cer`, `.crt`, `.pem`, `.der` and `.cert`; other
files are ignored, and a directory with no matching file is an error. Each certificate must match one of the
supplied thumbprints, so the number of pinned values is not required to equal the number of files.

## Import into CurrentUser without elevation

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256-root>' `
    -StoreLocation CurrentUser -Confirm:$false
```

`CurrentUser` needs no administrator rights. The trust applies to one user profile; services running under
another account do not see it. LocalMachine writes without elevation are refused with a validation error
(exit code `2`), never silently redirected.

## A JSON report for automation

```powershell
$report = Import-CaCertificate -Uri 'https://ca.example.com/root.pem' `
    -Thumbprint '<sha256-root>' -Confirm:$false -Json
$report | Out-File -LiteralPath 'C:\logs\ca-import.json' -Encoding utf8NoBOM
```

`-Json` returns one envelope and, unless `-LogLevel` is passed explicitly, suppresses the information log so
stdout parses as JSON. The shape is:

```json
{
  "Version": "2.0.1",
  "Timestamp": "2026-11-06T12:00:00.0000000Z",
  "Summary": {
    "Imported": 1,
    "Replaced": 0,
    "AlreadyPresent": 0,
    "Skipped": 0,
    "Declined": 0,
    "WhatIf": 0,
    "Total": 1,
    "UnverifiedRoot": false
  },
  "Results": [
    {
      "Timestamp": "2026-11-06T12:00:00.0000000Z",
      "SourceType": "Uri",
      "Source": "https://ca.example.com/root.pem",
      "Subject": "CN=Example Root CA, O=Example, C=US",
      "Issuer": "CN=Example Root CA, O=Example, C=US",
      "SerialNumber": "...",
      "ThumbprintSha1": "...",
      "ThumbprintSha256": "<sha256-root>",
      "NotBefore": "2025-01-01T00:00:00.0000000Z",
      "NotAfter": "2035-01-01T00:00:00.0000000Z",
      "IsCA": true,
      "IsSelfSigned": true,
      "StoreLocation": "LocalMachine",
      "StoreName": "Root",
      "Status": "Imported",
      "Reason": ""
    }
  ]
}
```

`Results` is always an array, even for a single certificate.

## Write an audit log

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256-root>' `
    -LogFile 'C:\logs\ca-import.log' -LogLevel Verbose -Confirm:$false
```

Log lines look like `[yyyy-MM-dd HH:mm:ss] [Level] message` with levels `Error`, `Warning`, `Info` and
`Verbose`. The log file is UTF-8 without BOM and is appended to, not overwritten; the parent directory must
exist. Warnings are also written to the PowerShell warning stream.

## Offline / air-gapped host

On a connected machine, download the certificate and compute the fingerprint from the file:

```powershell
Invoke-WebRequest -Uri 'https://ca.example.com/root.cer' -OutFile '.\root.cer'
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('.\root.cer')
[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($cert.RawData))
```

Copy the certificate file and the fingerprint to the isolated host, then dry-run and import:

```powershell
Import-CaCertificate -Path 'D:\transfer\root.cer' -Thumbprint '<sha256-root>' -WhatIf -Confirm:$false
Import-CaCertificate -Path 'D:\transfer\root.cer' -Thumbprint '<sha256-root>' -Confirm:$false
```

No network access is used with `-Path`. This is the recommended pattern for high-value hosts, because the
file and the fingerprint travel separately from the machine that fetched the file.

## Replace an existing copy

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256-root>' -Force -Confirm:$false
```

`-Force` removes an entry with the same SHA-256 fingerprint and writes the supplied certificate as
`Replaced`. It does not remove entries with a different fingerprint, and it never bypasses validation or the
fingerprint check.

## Trust a specific end-entity certificate

```powershell
Import-CaCertificate -Path 'C:\certs\partner-leaf.pem' -Thumbprint '<sha256-leaf>' `
    -StoreName TrustedPeople -Confirm:$false
```

A non-CA certificate is refused by the automatic routing and by the `Root`, `CA` and `AuthRoot` stores. It
is accepted only with an explicit `-StoreName TrustedPeople`, which is explicit trust for one peer, not a
CA trust anchor.

## Automation with exit codes

```powershell
$log = 'C:\logs\ca-import-{0:yyyyMMdd}.log' -f (Get-Date)
$json = Import-CaCertificate -Uri 'https://ca.example.com/root.cer' `
    -Thumbprint '<sha256-root>' -Confirm:$false -Json -LogFile $log
$json | Out-File -LiteralPath 'C:\logs\ca-import.json' -Encoding utf8NoBOM
if ($LASTEXITCODE -ne 0) {
    # 1 = operational failure, 2 = security or validation refusal
    Send-MailMessage -To 'pki@example.com' -Subject 'CA import failed' -Body $json
}
```

`$LASTEXITCODE` is set only when the wrapper runs as a child process (`pwsh -File`). When calling the module
function directly, use `try`/`catch` and inspect `$_.Exception.Data['CaExitCode']`; the module never calls
`exit`.

## Validate a directory before importing

```powershell
Get-ChildItem 'C:\certs\corporate-cas' -File | ForEach-Object {
    Import-CaCertificate -Path $_.FullName -Thumbprint '<sha256>' -WhatIf -Confirm:$false -PassThru
}
```

This reports one result per file with status `WhatIf` and no store write, which is a cheap way to find the
one file whose fingerprint does not match before the real run.

## Undo an import

```powershell
$result = Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256-root>' `
    -Confirm:$false -PassThru
$result | Format-List Subject, ThumbprintSha1, ThumbprintSha256, Status
Remove-Item -Path "Cert:\LocalMachine\Root\$($result.ThumbprintSha1)"
```

`ThumbprintSha1` is the value `certmgr.msc` and `certutil` use to address the certificate; the SHA-256 value
is the identity check. If the certificate existed before a `-Force` replacement, rolling back means
importing the original copy again from a trusted source, because the replaced entry is gone.

More worked examples with hMailServer, Exim and IIS are in
[docs/EXAMPLES.md](../docs/EXAMPLES.md). Parameter
semantics are in [Parameters](05-Parameters.md); refusals are decoded in
[Troubleshooting](07-Troubleshooting.md).
