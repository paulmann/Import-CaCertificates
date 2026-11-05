# Agent guide — Import-CaCertificates 2.0.1

Operational detail behind the [AGENTS.md](../AGENTS.md) map: every parameter, the exact
expected output of each step, the failure-mode table and the rollback procedure. Read
[AGENTS.md](../AGENTS.md) first; it carries the preconditions and the short list of
prohibitions. Human overview: [README.md](../README.md).

> Verified against repository state on 2026-11-06: version 2.0.1 (`VERSION`, module
> manifest), MIT License, `#Requires -Version 7.4`, 38 Pester tests (33 unit + 5
> integration), PSScriptAnalyzer 1.25.0 clean.

## 1. Entry points and repository layout

| Path | Purpose |
|---|---|
| `Import-CaCertificates.ps1` | Command-line wrapper; loads the module from `src/` and maps exceptions to exit codes |
| `src/Import-CaCertificates/Import-CaCertificates.psd1` | Module manifest: version 2.0.1, exported function `Import-CaCertificate` |
| `src/Import-CaCertificates/Import-CaCertificates.psm1` | Implementation: parsing, validation, store writes, logging |
| `tests/` | Pester unit tests and gated integration tests, plus shared helpers |
| `tools/New-Release.ps1` | Builds the release ZIP and `SHA256SUMS.txt` |
| `docs/` | This guide, the security model and service examples |
| `PSScriptAnalyzerSettings.psd1` | Static-analysis configuration used by CI |

## 2. Requirements and supported platforms

| Item | Requirement |
|---|---|
| Operating system | Windows 10 1607 or newer, Windows 11, Windows Server 2012 R2 or newer |
| PowerShell | 7.4 or newer (`pwsh`); `#Requires -Version 7.4` enforces it. Windows PowerShell 5.1 is not supported |
| Elevation | Required for `LocalMachine`; not required for `-StoreLocation CurrentUser` |
| Network | Outbound HTTPS to every `-Uri` host; `http://` is refused before any request |
| Fingerprint | The expected SHA-256 fingerprint (64 hex characters) for every certificate, obtained from the CA's published page |
| Disk | A unique temporary directory under `-TempPath` (default `$env:TEMP`), removed after the run unless `-KeepTempFiles` |
| Distribution | Release archive from GitHub Releases, or the source tree. There is no PSGallery package |

The module is Windows-only: it uses `WindowsIdentity`, `X509Store` and the Windows
certificate stores. It does not run on Linux or macOS.

## 3. Install from a release

1. Download `Import-CaCertificates-2.0.1.zip` and `SHA256SUMS.txt` from
   <https://github.com/paulmann/Import-CaCertificates/releases/latest>.
2. Compute the archive hash and compare it with the line for this archive in
   `SHA256SUMS.txt`. A mismatch means the download is not the published build; stop.
3. Extract the archive. The wrapper resolves the module relative to its own directory, so
   the extracted folder can be moved as a whole.

```powershell
(Get-FileHash -Algorithm SHA256 -LiteralPath .\Import-CaCertificates-2.0.1.zip).Hash
Get-Content -LiteralPath .\SHA256SUMS.txt
```

## 4. Install from source and verify

```powershell
git clone https://github.com/paulmann/Import-CaCertificates.git
Import-Module .\Import-CaCertificates\src\Import-CaCertificates\Import-CaCertificates.psd1
```

Verify before the first real run. Three numbers and one export must match; if any differs,
stop and report rather than continuing with a partial install.

```powershell
(Get-Module Import-CaCertificates).Version.ToString()        # 2.0.1
(Get-Module Import-CaCertificates).ExportedFunctions.Keys   # Import-CaCertificate
$parameters = (Get-Command Import-CaCertificate).Parameters.Keys
$parameters -contains 'Thumbprint'                          # True
$parameters -contains 'RequireConfirmation'                 # True
Get-Help Import-CaCertificate -Full                         # comment-based help renders
```

## 5. Parameters

The module function `Import-CaCertificate` and the CLI wrapper accept the same parameters.
There is no configuration file and no environment variable: behaviour is set only by
parameters.

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `-Uri` | string[] | — | HTTPS URL(s) returning PEM, DER or a multi-certificate PEM; mandatory in the `ByUri` set |
| `-Path` | string[] | — | file(s) or directory of `.cer`, `.crt`, `.pem`, `.der`, `.cert`; mandatory in the `ByPath` set |
| `-Thumbprint` | string[] | — | expected SHA-256 fingerprint(s); every imported certificate must match one |
| `-StoreLocation` | string | `LocalMachine` | `LocalMachine` (elevated) or `CurrentUser` (no elevation) |
| `-StoreName` | string | auto | `Root`, `CA`, `AuthRoot` or `TrustedPeople`; auto routes a self-signed CA to Root and another CA to CA |
| `-NoRootImport` | switch | off | skip Root CA certificates in the batch |
| `-AllowUnverifiedRoot` | switch | off | explicit override of the fingerprint requirement for Root CA; warned and reported |
| `-RequireConfirmation` | switch | off | interactive yes/no per certificate; unusable non-interactively |
| `-Force` | switch | off | replace a certificate with the same SHA-256 fingerprint; never bypasses verification |
| `-PassThru` | switch | off | return result objects |
| `-Json` | switch | off | return one JSON envelope; suppresses informational output unless `-LogLevel` is given |
| `-LogLevel` | string | `Info` | `None`, `Error`, `Warning`, `Info`, `Verbose` |
| `-LogFile` | string | — | append log lines to a file (UTF-8, no BOM) |
| `-KeepTempFiles` | switch | off | keep downloaded files and report the directory |
| `-TempPath` | string | `$env:TEMP` | parent directory for the unique temporary directory |
| `-SkipChainValidation` | switch | off | skip the root/intermediate chain check |
| `-WhatIf` | common | — | `ShouldProcess`: report the intended write, change nothing |
| `-Confirm` | common | — | `ConfirmImpact = High`, so automation must pass `-Confirm:$false` |

The CLI wrapper also accepts the deprecated `-RootUrl` and `-IntermediateUrl` (mapped to
`-Uri` with a warning) and `-KeepFiles` (alias of `-KeepTempFiles`). The module function
accepts `-Uri` only.

## 6. Run order

Run in this order and do not skip a step: help, dry run, import, verify the store, restart
the dependent service.

### 6.1 Read the documentation

```powershell
Get-Help Import-CaCertificate -Full
```

### 6.2 Dry run

No store change happens; `-WhatIf` reports what would be written.

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

Expected output, in this order:

```text
[<timestamp>] [Info] Certificate: Subject='CN=ISRG Root X1, ...', SHA-256=96BCEC06...
What if: Performing the operation "Import certificate ..." on target "LocalMachine\Root"
Finished: total=1, imported=0, whatIf=1, ...
```

### 6.3 Import

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru
```

Expected: a status of `Imported` (or `AlreadyPresent` on a repeat) and a `Finished:` line.
Root certificates are written to `LocalMachine\Root`, intermediates to `LocalMachine\CA`.

### 6.4 Verify the store

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG' |
    Select-Object Subject, Thumbprint, NotAfter
```

Compare the SHA-1 `Thumbprint` with the `-Thumbprint` value converted, or re-read the
certificate SHA-256 with `Get-FileHash` on the downloaded file. Exit code `0` alone is not
proof: dry runs, `AlreadyPresent` and `Skipped` also return `0`.

### 6.5 Restart the dependent service

A service that already failed with `Unknown CA` caches its chain. Restart it and test the
connection again:

```powershell
Restart-Service -Name hMailServer
Restart-Service -Name W3SVC
```

Use the service named in the original error; restarting an unrelated service proves
nothing.

## 7. Output, statuses and exit codes

- Informational lines use the format `[yyyy-MM-dd HH:mm:ss] [Level] message`, with levels
  `Error`, `Warning`, `Info` and `Verbose`. Warnings also go to the warning stream.
- `-Json` returns a single envelope with `Version`, `Timestamp`, `Summary` and `Results`.
  `-LogFile` appends the same lines as plain text.
- Result statuses: `Imported`, `Replaced`, `AlreadyPresent`, `Skipped`, `WhatIf`,
  `Declined`.
- Exit codes: `0` finished (verify the store), `1` operational failure, `2` security or
  validation refusal.

A `2` is a deliberate refusal, not a bug: non-HTTPS URL, missing or mismatched
fingerprint, a non-CA certificate, an expired certificate, private key material, a PFX,
a chain mismatch, or a `LocalMachine` write without elevation. Report the exit code
together with the message; do not work around it.

## 8. Failure modes

| Symptom | Likely cause | Action |
|---|---|---|
| `Root CA import of '<subject>' requires an expected SHA-256 fingerprint` | Root CA without `-Thumbprint` | provide the pinned SHA-256, or use `-AllowUnverifiedRoot` only deliberately |
| `Invalid -Thumbprint value ... SHA-1` | 40-hex SHA-1 thumbprint | compute the SHA-256 fingerprint (64 hex characters) |
| `does not match any expected -Thumbprint value` | wrong certificate or wrong pin | re-check the source page and the fingerprint |
| `Only https:// URLs are allowed` | `http://` URL | use the HTTPS URL published by the CA |
| `Failed to download certificate from '<url>'` | firewall, proxy or TLS interception | confirm outbound HTTPS; do not bypass the check |
| `contains a private key` or `PFX/P12` | private key material in the input | export the public certificate and retry |
| `failed validation: the certificate is expired` | stale certificate | obtain the current certificate from the CA |
| `does not chain to the supplied root certificate(s)` | mismatched pair | download the matching root and intermediate |
| `LocalMachine certificate stores require an elevated session` | not elevated | start an elevated `pwsh`, or use `-StoreLocation CurrentUser` |
| `NonInteractive mode` and no import | confirmation prompt in automation | pass `-Confirm:$false`; use `-WhatIf` for dry runs |
| `Certificate already exists ... Skipping` | idempotent repeat | add `-Force` only when replacement is intended |
| `Unknown CA` still reported | the service cached its chain | restart the service |

## 9. Safety, rollback and temporary files

What changes: one store entry per imported certificate (machine-wide trust for a Root CA)
and a temporary download directory that is normally deleted.

What does not change: private keys, other certificates, services, configuration files,
registry data outside the certificate store. The tool contacts nothing except the supplied
URLs.

Rollback of one imported certificate (elevated; the SHA-1 thumbprint is reported as
`ThumbprintSha1`):

```powershell
Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<SHA-1-thumbprint>
```

If `-KeepTempFiles` was used, delete the directory named after `Temporary files retained
at:`. On a production host: `-WhatIf`, then one certificate, then verify the store, then
the intermediate, then restart the service. Never import a Root CA "to see what happens".

## 10. Limits and non-goals

- No OCSP, CRL or certificate-transparency checks, and no revocation handling.
- No proxy or TLS options, no built-in certificate URLs, no uninstall path.
- One certificate per URL or file, although a multi-certificate PEM and a directory are
  supported.
- Self-signed detection compares subject and issuer names; a cross-signed root is treated
  as an intermediate.
- Legacy `-RootUrl` and `-IntermediateUrl` work only through the CLI wrapper.
- 1.x is not supported: 2.0.0 replaced it because Root CA imports could be made without
  fingerprint verification.

## 11. Self-verification for contributors

Run the suite and the linter on Windows before opening a pull request:

```powershell
Invoke-Pester -Path .\tests -Output Detailed
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

The suite is 38 Pester tests: 33 unit tests and 5 integration tests. Integration tests are
gated: network tests run only when `$env:CI` is set, and `LocalMachine` store tests run
only on an elevated CI runner. Do not enable a gate to make a test pass; write a unit test
with `-WhatIf` or `-StoreLocation CurrentUser` instead.

## 12. Reporting bugs and vulnerabilities

Bugs and compatibility reports go to
<https://github.com/paulmann/Import-CaCertificates/issues/new/choose>. Include the version,
the Windows build, the PowerShell version, the exact command with secrets redacted, the
exit code and the `-Json` envelope or `-LogFile` lines.

Security problems never go to a public issue: follow [SECURITY.md](../SECURITY.md), which
uses the repository's private vulnerability reporting. The disclosure timeline is stated
there.

## 13. Sources of truth

| Document | Contains |
|---|---|
| [AGENTS.md](../AGENTS.md) | the map: preconditions, commands, exit codes, traps |
| [README.md](../README.md) | overview, requirements, install, quick start, parameters, troubleshooting |
| [docs/SECURITY-MODEL.md](SECURITY-MODEL.md) | threat model, verification order, limits |
| [docs/EXAMPLES.md](EXAMPLES.md) | hMailServer, Exim, IIS and scheduled-task scenarios |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | tests, style, commit and release process |
| [SECURITY.md](../SECURITY.md) | private disclosure policy and supported versions |
| [CHANGELOG.md](../CHANGELOG.md) | changes and breaking changes per version |
| `tools/New-Release.ps1` | how the release archive and `SHA256SUMS.txt` are built |
