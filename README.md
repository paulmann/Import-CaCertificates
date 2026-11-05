# Import-CaCertificates

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates/releases/latest)
[![PowerShell](https://img.shields.io/badge/powershell-7.4%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-lightgrey.svg)](LICENSE)

<!-- md-i18n:switcher -->
**Read this in:** English · [Deutsch](README.de.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

- [1. Overview](#1-overview)
- [2. What changed in 2.0.0](#2-what-changed-in-200)
- [3. Features](#3-features)
- [4. Security model](#4-security-model)
- [5. Requirements](#5-requirements)
- [6. Install](#6-install)
- [7. Quick start](#7-quick-start)
- [8. Usage examples](#8-usage-examples)
- [9. Parameters](#9-parameters)
- [10. Import results and exit codes](#10-import-results-and-exit-codes)
- [11. Migration from 1.x](#11-migration-from-1x)
- [12. Troubleshooting](#12-troubleshooting)
- [13. Development](#13-development)
- [14. License and support](#14-license-and-support)

***

## 1. Overview

**Import-CaCertificates** imports public CA certificates (Root and Intermediate) into
Windows certificate stores. It is meant for servers behind restrictive firewalls and
for deployments that must trust a specific CA chain — for example hMailServer, Exim on
Windows, IIS, or an internal corporate PKI.

The utility is deliberately narrow in scope: it downloads or reads public certificates,
verifies that they are the certificates you expect, and imports them into
`LocalMachine` or `CurrentUser` stores. It does not request, renew, back up, list or
remove certificates, and it never imports private keys.

Importing a Root CA is a machine-wide trust decision. Version 2.0.0 therefore requires
an expected SHA-256 fingerprint for every imported certificate and refuses a Root CA
import without one unless the explicit `-AllowUnverifiedRoot` switch is used.

## 2. What changed in 2.0.0

Version 2.0.0 is a security-focused rewrite. The behavior of the command changed
intentionally; see [CHANGELOG.md](CHANGELOG.md) and
[Migration from 1.x](#11-migration-from-1x) before upgrading.

- The single script became a module (`Import-CaCertificate`) plus a thin CLI wrapper.
- Root CA imports require a pinned SHA-256 fingerprint; the old `-RootUrl`-only flow
  is refused instead of trusted silently.
- Plain HTTP URLs, PFX/P12 files and files containing private keys are refused.
- Certificates are validated (validity period, CA role, Key Usage, signature
  algorithm), and a Root/Intermediate pair is chain-checked before import.
- Multi-certificate PEM bundles, local files and directories are supported.
- Deduplication uses the SHA-256 fingerprint (the SHA-1 thumbprint is reported but is
  not the identity check).
- Structured results (`-PassThru`), JSON reports (`-Json`), log files (`-LogFile`),
  exit codes and Pester/PSScriptAnalyzer CI were added.

## 3. Features

- **Explicit trust anchoring**: every imported certificate must match an expected
  SHA-256 fingerprint passed with `-Thumbprint`.
- **Safe defaults for Root CAs**: a Root CA import without a fingerprint is refused;
  `-AllowUnverifiedRoot` is the explicit, loudly reported override.
- **HTTPS only**: `http://` URLs are rejected before any request is made.
- **Public certificates only**: PFX/P12 files and any file containing a private key
  are refused.
- **Validation**: X.509 parsing, `NotBefore`/`NotAfter`, Basic Constraints `CA=true`,
  Key Usage `keyCertSign`, broken signature algorithms (MD2/MD5) and weak key sizes.
- **Chain validation**: when a root and an intermediate arrive in the same batch, the
  intermediate must chain to the supplied root (`-SkipChainValidation` to opt out).
- **Flexible input**: HTTPS URL, local PEM/DER file, base64 DER, multi-certificate PEM
  bundle, or a directory of certificate files.
- **Idempotent store writes**: a certificate with the same SHA-256 fingerprint is
  skipped; `-Force` replaces an existing copy but never skips verification.
- **Automation friendly**: `-WhatIf`, `-Confirm`, `-PassThru`, `-Json`, `-LogFile`,
  `-LogLevel`, and distinct exit codes.
- **Windows stores**: `LocalMachine` (default, elevated) and `CurrentUser`, stores
  `Root`, `CA`, `AuthRoot` and `TrustedPeople`.

## 4. Security model

The full threat model is in [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md). The short
version:

1. **Only HTTPS** is accepted for downloads.
2. **The expected SHA-256 fingerprint is mandatory** for every imported certificate.
   For a Root CA it is mandatory unless `-AllowUnverifiedRoot` is passed explicitly.
3. **The certificate is validated before any store write**: parsed as X.509, inside its
   validity period, marked as a CA, allowed to sign certificates, and signed with an
   acceptable algorithm.
4. **The certificate is not a private key**: files that contain private keys, and
   PFX/P12 containers, are refused.
5. **Confirmation is the default**: `ConfirmImpact = High` means an interactive run
   asks before writing; non-interactive automation must pass `-Confirm:$false`.
6. **No telemetry, no hidden network access**: the only network requests are the
   `-Uri` values you provide.

A pinned fingerprint protects against a swapped download, a compromised mirror, or a
wrong file. It does not protect against a CA that legitimately re-issued a different
root — that is why the fingerprint must come from the CA's own published page or from
your PKI documentation, not from the same URL you are downloading from.

## 5. Requirements

| Requirement | Details |
|---|---|
| Operating system | Windows 10 (1607 or later), Windows 11, Windows Server 2012 R2 or later |
| PowerShell | 7.4 or later (`pwsh`). Windows PowerShell 5.1 is not supported. |
| Permissions | Local administrator for `-StoreLocation LocalMachine`; no elevation for `-StoreLocation CurrentUser` |
| Network | HTTPS access to each `-Uri` host; not needed with `-Path` |
| Windows 7 / 8.1 | Not supported: PowerShell 7 does not install there. Version 1.x claimed support it did not have. |

Tested by CI on `windows-latest` with PowerShell 7.4/7.5 and Pester 5.7.1; developed
and tested locally on Windows 11 with PowerShell 7.6. Other combinations are expected to
work but are not covered by CI.

## 6. Install

### From a release (recommended)

Download the latest `Import-CaCertificates-<version>.zip` and `SHA256SUMS.txt` from the
[Releases page](https://github.com/paulmann/Import-CaCertificates/releases/latest),
verify the archive, and extract it to a tools directory such as `C:\Tools\Import-CaCertificates`:

```powershell
$expected = (Select-String -Path .\SHA256SUMS.txt -Pattern '\.zip$').Line.Split(' ')[0]
(Get-FileHash -Algorithm SHA256 -LiteralPath .\Import-CaCertificates-2.0.0.zip).Hash -eq $expected
Expand-Archive -LiteralPath .\Import-CaCertificates-2.0.0.zip -DestinationPath C:\Tools\Import-CaCertificates
```

The archive contains the module (`src/Import-CaCertificates`), the CLI wrapper, the
documentation and the license. The wrapper locates the module relative to itself, so
the extracted directory can be moved as a whole.

### From source

```powershell
git clone https://github.com/paulmann/Import-CaCertificates.git
cd Import-CaCertificates
```

There is no installer and no PSGallery package yet. Import the module directly:

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Command Import-CaCertificate
```

### Verify

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Help Import-CaCertificate -Full
```

## 7. Quick start

**Step 1 — obtain the expected SHA-256 fingerprint from the CA's published page.** If the
CA publishes the certificate file, compute the fingerprint yourself and compare it with
the value the CA publishes elsewhere:

```powershell
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('C:\certs\ca.pem')
[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($cert.RawData))
```

**Step 2 — dry run.** `-WhatIf` downloads, parses, validates and prints the plan; it
does not write to the store:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

`96BCEC06…` is the SHA-256 fingerprint of ISRG Root X1 as published by Let's Encrypt;
it is shown here as a working example, not as a recommendation to trust any CA.

**Step 3 — import.** Without `-Confirm:$false` an interactive session asks for
confirmation before each store write. Automation must pass `-Confirm:$false`:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru
```

**Step 4 — verify the store.**

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG Root X1'
```

Restart the service that reported the unknown CA (for example hMailServer) so that it
re-reads the machine trust store.

## 8. Usage examples

### Import a Root CA from a local file

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -StoreLocation LocalMachine -Confirm:$false
```

### Import an Intermediate CA only

A non-self-signed CA certificate is routed to `LocalMachine\CA` automatically:

```powershell
Import-CaCertificate -Path 'C:\certs\intermediate.pem' -Thumbprint '<sha256>' -Confirm:$false
```

### Import a bundle, skip the Root

A multi-certificate PEM may contain a root and one or more intermediates. Pin every
certificate you import; `-NoRootImport` skips the root:

```powershell
Import-CaCertificate -Path 'C:\certs\chain.pem' `
    -Thumbprint '<sha256-intermediate-1>', '<sha256-intermediate-2>' `
    -NoRootImport -Confirm:$false
```

### Import a directory of certificates

```powershell
Import-CaCertificate -Path 'C:\certs\corporate-cas' -Thumbprint '<sha256-1>', '<sha256-2>' -WhatIf -Confirm:$false
```

### Automation with a JSON report

```powershell
$report = Import-CaCertificate -Uri 'https://ca.example.com/root.pem' `
    -Thumbprint '0123...' -Confirm:$false -Json
$report | Out-File -LiteralPath 'C:\logs\ca-import.json' -Encoding utf8NoBOM
```

`-Json` returns one JSON envelope (`Version`, `Timestamp`, `Summary`, `Results`). With
`-Json` the information log is suppressed unless `-LogLevel` is passed explicitly, so
stdout contains only the JSON document.

### Log to a file

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' `
    -LogFile 'C:\logs\ca-import.log' -LogLevel Verbose -Confirm:$false
```

### Offline / air-gapped host

1. Download the certificate on another machine and verify its fingerprint.
2. Copy the PEM/DER file (and its SHA-256) to the target host.
3. Run `Import-CaCertificate -Path ... -Thumbprint ... -Confirm:$false`.

### Replace an existing copy

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' -Force -Confirm:$false
```

`-Force` replaces a certificate with the same SHA-256 fingerprint; it does not bypass
the fingerprint check.

### Undo an import

```powershell
Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<SHA-1-thumbprint>
```

Every result object reports `ThumbprintSha1` (for `certmgr.msc` / `certutil`) and
`ThumbprintSha256` (the identity check).

More scenarios: [docs/EXAMPLES.md](docs/EXAMPLES.md).

## 9. Parameters

### Module command `Import-CaCertificate`

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Uri` | string[] | — | HTTPS URL(s) of certificate files (PEM, DER, base64 DER, or a multi-certificate PEM bundle). Mandatory in the `ByUri` parameter set. |
| `-Path` | string[] | — | Local certificate file(s) or directories of `.cer/.crt/.pem/.der/.cert` files. Mandatory in the `ByPath` parameter set. |
| `-Thumbprint` | string[] | — | Expected SHA-256 fingerprint(s), 64 hex characters; spaces, colons and dashes are ignored. Every imported certificate must match one of the values. |
| `-StoreLocation` | string | `LocalMachine` | `LocalMachine` (requires elevation) or `CurrentUser`. |
| `-StoreName` | string | auto | `Root`, `CA`, `AuthRoot` or `TrustedPeople`. Without it, a self-signed CA goes to `Root` and a non-self-signed CA to `CA`. |
| `-NoRootImport` | switch | off | Skip Root CA certificates instead of importing them. |
| `-AllowUnverifiedRoot` | switch | off | Permit a Root CA import without `-Thumbprint`. Explicit trust decision; a warning is logged and the run is reported as unverified. |
| `-RequireConfirmation` | switch | off | Ask for an interactive yes/no confirmation for every certificate, in addition to `ShouldProcess`. Not usable in non-interactive sessions. |
| `-Force` | switch | off | Replace an existing certificate with the same SHA-256 fingerprint. |
| `-PassThru` | switch | off | Return one result object per certificate. |
| `-Json` | switch | off | Return a single JSON envelope (`Version`, `Timestamp`, `Summary`, `Results`). |
| `-LogLevel` | string | `Info` | `None`, `Error`, `Warning`, `Info` or `Verbose`. |
| `-LogFile` | string | — | Append log lines (UTF-8, no BOM) to this file. |
| `-KeepTempFiles` | switch | off | Keep downloaded files in the temporary directory. |
| `-TempPath` | string | `$env:TEMP` | Parent directory for a unique temporary download directory, removed afterwards. Existing files are never deleted. |
| `-SkipChainValidation` | switch | off | Skip the signature-chain check between the supplied roots and intermediates. |
| `-WhatIf` / `-Confirm` | common | — | Standard `ShouldProcess` behavior. |

### CLI wrapper `Import-CaCertificates.ps1`

The wrapper accepts the same parameters plus two deprecated compatibility switches
mapped to `-Uri`:

| Parameter | Status | Description |
|---|---|---|
| `-RootUrl` | deprecated | HTTPS URL of a Root CA certificate. Use `-Uri`. |
| `-IntermediateUrl` | deprecated | HTTPS URL of an Intermediate CA certificate. Use `-Uri`. |
| `-KeepFiles` | alias | Alias of `-KeepTempFiles` (the 1.x README used this name). |

The wrapper must be started from an extracted release directory (or the repository
root); it loads `src/Import-CaCertificates/Import-CaCertificates.psd1` relative to its
own location.

## 10. Import results and exit codes

Each certificate produces one of the following statuses:

| Status | Meaning |
|---|---|
| `Imported` | Certificate written to the target store and verified by reading it back. |
| `Replaced` | An existing certificate with the same SHA-256 fingerprint was replaced (`-Force`). |
| `AlreadyPresent` | The same certificate is already in the store; nothing was written. |
| `Skipped` | The certificate was excluded by policy (`-NoRootImport`). |
| `WhatIf` | Dry run: the certificate passed all checks but was not written. |
| `Declined` | The interactive confirmation was answered with "no". |

CLI exit codes:

| Code | Meaning |
|---|---|
| `0` | The run finished (including dry runs, skipped duplicates and declined confirmations). Verify the store before treating this as "imported". |
| `1` | Operational failure: download, file system, store access, module not found. |
| `2` | Security or validation refusal: plain HTTP, missing/failed fingerprint, not a CA, expired, private key, PFX, chain mismatch, not elevated for `LocalMachine`. |

## 11. Migration from 1.x

| 1.x | 2.0.0 |
|---|---|
| `-RootUrl` and `-IntermediateUrl` | `-Uri` (a list); the deprecated names still work in the CLI wrapper and log a warning. |
| No fingerprint check | `-Thumbprint` is mandatory for every certificate; Root CA imports are refused without it unless `-AllowUnverifiedRoot` is used. |
| `-KeepFiles` (documented) / `-KeepTempFiles` (implemented) | `-KeepTempFiles`; `-KeepFiles` is an alias. |
| `-TempPath` removed after the run | A unique subdirectory is created under `-TempPath` and removed; existing files are not touched. |
| Single certificate per URL | Multi-certificate PEM bundles, directories and `-Path` are supported. |
| Root/intermediate chosen by parameter | Chosen by certificate type, or forced with `-StoreName`. |
| Windows 7 / Server 2012 R2 claim | Windows 10 1607+/11, Windows Server 2012 R2+ with PowerShell 7.4+. Windows 7 is not supported. |
| Console log only | `-PassThru`, `-Json`, `-LogFile`, `-LogLevel` and exit codes. |

## 12. Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| `Root CA import ... requires an expected SHA-256 fingerprint` | Root CA imported without `-Thumbprint` | Get the fingerprint from the CA's published page and pass it. |
| `Invalid -Thumbprint value ... SHA-1 thumbprint` | The value is a 40-hex SHA-1 thumbprint | Compute the SHA-256 fingerprint (64 hex characters). |
| `does not match any expected -Thumbprint value` | Wrong certificate or wrong fingerprint | Compare subject, issuer and the printed SHA-256 with the source. |
| `Only https:// URLs are allowed` | `http://` URL | Use the CA's HTTPS URL; do not work around the check. |
| `contains a private key` / `PFX/P12` | The file contains private key material | Export the public certificate (`Export-Certificate -Type CERT`) and import that. |
| `failed validation: the certificate is expired` | Expired certificate | Obtain the current certificate from the CA. |
| `does not chain to the supplied root certificate(s)` | Root and intermediate do not belong together | Download the matching pair, or import only the certificate you need. |
| `LocalMachine certificate stores require an elevated session` | Not running as Administrator | Start an elevated `pwsh`, or use `-StoreLocation CurrentUser`. |
| `NonInteractive mode` error | Default confirmation prompt in automation | Pass `-Confirm:$false` (and `-WhatIf` for dry runs). |
| `Unknown CA` remains after import | The dependent service cached its chain | Restart the service. |

## 13. Development

```powershell
# Tests (Pester 5.7.1 and 6.x are both supported)
Install-Module Pester -RequiredVersion 5.7.1 -Force -Scope CurrentUser
Invoke-Pester -Path .\tests -Output Detailed

# Static analysis (runs in CI as well)
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1

# Build a release archive and checksums
.\tools\New-Release.ps1 -Version v2.0.0 -OutputDirectory .\out
```

Integration tests are gated: network tests run when `$env:CI` is set, and LocalMachine
tests run only on an elevated CI runner. See
[tests/Import-CaCertificates.Integration.Tests.ps1](tests/Import-CaCertificates.Integration.Tests.ps1).

CI runs PSScriptAnalyzer and Pester on every push and pull request; pushing a `v*` tag
builds the archive, verifies its SHA-256 and publishes the GitHub release.

## 14. License and support

### License

This project is licensed under the **PolyForm Noncommercial License 1.0.0** — see
[LICENSE](LICENSE). Commercial use requires a separate license; contact the author.
If your use case is commercial or you need a permissive license, open an issue to
discuss licensing before adopting the tool.

### Author

Mikhail Deynekin — [GitHub: paulmann](https://github.com/paulmann) —
m@deynekin.com

### Security reports

Please do not open public issues for security problems. See [SECURITY.md](SECURITY.md).

### Support the project

If this tool resolved a certificate problem for you, cite it in your runbook with the
version and link. Do not create stars, forks or comments automatically.
