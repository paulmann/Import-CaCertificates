# AGENTS.md — Import-CaCertificates 2.0.1

Agent-facing guide: how to install, run and report problems for Import-CaCertificates.
Human documentation: [README.md](README.md). Security model:
[docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md).

> Verified against repository state on 2026-11-06. Version covered: 2.0.1 (VERSION,
> module manifest, README badge; MIT License). Tests: 38 Pester tests, 36 passed / 2
> skipped locally (skips are CI-gated network and LocalMachine tests), PSScriptAnalyzer
> clean.

## 1. What it is

`Import-CaCertificate` (module `Import-CaCertificates`) reads public CA certificates
from HTTPS URLs or local files and imports them into Windows certificate stores. It is
not a certificate manager: it does not request, renew, back up, list or remove
certificates, and it never imports private keys.

| | |
|---|---|
| Runtime | Windows 10 1607+/11, Windows Server 2012 R2+; PowerShell 7.4+ (`pwsh`), enforced by `#Requires -Version 7.4`; Windows PowerShell 5.1 is not supported |
| Entry points | Module function `Import-CaCertificate` in `src/Import-CaCertificates/`; CLI wrapper `Import-CaCertificates.ps1` |
| Writes to | One certificate per input into `Cert:\<StoreLocation>\<StoreName>`: default `LocalMachine\Root` for a self-signed CA and `LocalMachine\CA` for an intermediate; `-StoreLocation CurrentUser` needs no elevation; a unique temporary download directory, removed afterwards unless `-KeepTempFiles` |
| Network | Only the `-Uri` values supplied; HTTPS enforced, `http://` refused before any request |
| Elevation | Required for `LocalMachine` (`Test-IsAdministrator` check, exit code 2), not for `CurrentUser` |

## 2. Preconditions

| Requirement | Why | Check |
|---|---|---|
| PowerShell 7.4+ | `#Requires -Version 7.4`; `.NET 8` APIs are used | `$PSVersionTable.PSVersion` |
| The expected SHA-256 fingerprint | Root CA imports are refused without it unless `-AllowUnverifiedRoot`; every certificate is pinned | fingerprint from the CA's published page, 64 hex characters |
| Elevated session for `LocalMachine` | the store is machine-wide | `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')` |
| HTTPS access to the `-Uri` host | certificates are downloaded at run time | `(Invoke-WebRequest -Uri '<url>' -Method Head).StatusCode` returns `200` |
| Approval of the trust decision | importing a Root CA changes machine-wide trust | the fingerprint and subject were confirmed by a human from an independent source |

If a check fails, stop and report. Do not lower the execution policy, do not use
`-AllowUnverifiedRoot` to get past a missing fingerprint, do not substitute the Current
User store, and do not extract certificates with another tool to avoid the HTTPS rule.

## 3. Install

### 3.1 From a release

Download `Import-CaCertificates-2.0.1.zip` and `SHA256SUMS.txt` from
<https://github.com/paulmann/Import-CaCertificates/releases/latest>, verify the hash and
extract the archive. The wrapper resolves the module relative to its own directory.

```powershell
(Get-FileHash -Algorithm SHA256 -LiteralPath .\Import-CaCertificates-2.0.1.zip).Hash
```

### 3.2 From source

```powershell
git clone https://github.com/paulmann/Import-CaCertificates.git
Import-Module .\Import-CaCertificates\src\Import-CaCertificates\Import-CaCertificates.psd1
```

### 3.3 Verify

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
(Get-Module Import-CaCertificates).Version.ToString()   # 2.0.1
Get-Command Import-CaCertificate | Select-Object -ExpandProperty Parameters
```

## 4. Configure

No configuration file and no environment variable; behaviour is set only by parameters.

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `-Uri` | string[] | — | HTTPS URL(s); mandatory in the `ByUri` set |
| `-Path` | string[] | — | file(s) or directory of `.cer/.crt/.pem/.der/.cert`; mandatory in the `ByPath` set |
| `-Thumbprint` | string[] | — | expected SHA-256 fingerprint(s); every imported certificate must match one |
| `-StoreLocation` | string | `LocalMachine` | `LocalMachine` (elevated) or `CurrentUser` |
| `-StoreName` | string | auto | `Root`, `CA`, `AuthRoot`, `TrustedPeople`; auto routes self-signed CA to Root and other CA to CA |
| `-NoRootImport` | switch | off | skip Root CA certificates |
| `-AllowUnverifiedRoot` | switch | off | explicit override of the fingerprint requirement for Root CA (warned, reported) |
| `-RequireConfirmation` | switch | off | interactive yes/no per certificate; unusable non-interactively |
| `-Force` | switch | off | replace a certificate with the same SHA-256 fingerprint; never bypasses verification |
| `-PassThru` | switch | off | return result objects |
| `-Json` | switch | off | return a JSON envelope; suppresses info logging unless `-LogLevel` is given |
| `-LogLevel` | string | `Info` | `None`, `Error`, `Warning`, `Info`, `Verbose` |
| `-LogFile` | string | — | append log lines (UTF-8, no BOM) |
| `-KeepTempFiles` | switch | off | keep downloaded files |
| `-TempPath` | string | `$env:TEMP` | parent for a unique temporary directory, removed after the run |
| `-SkipChainValidation` | switch | off | skip root/intermediate chain check |
| `-WhatIf` / `-Confirm` | common | — | `ShouldProcess`; `ConfirmImpact = High` means automation must pass `-Confirm:$false` |

The CLI wrapper also accepts the deprecated `-RootUrl`/`-IntermediateUrl` (mapped to
`-Uri` with a warning) and `-KeepFiles` (alias of `-KeepTempFiles`).

## 5. Use

Run in order: help, dry run, import, verify the store, restart the dependent service.

**5.1 Read the documentation**

```powershell
Get-Help Import-CaCertificate -Full
```

**5.2 Dry run (no store change)**

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

Expected: `[<timestamp>] [Info] Certificate: Subject='CN=ISRG Root X1, ...', ... SHA-256=96BCEC06...`,
a `What if: Performing the operation "Import certificate ..." on target "LocalMachine\Root"`
line, and `Finished: total=1, ... whatIf=1`. No store write.

**5.3 Import**

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru
```

Expected: status `Imported` (or `AlreadyPresent` on a repeat) and
`Finished: total=1, imported=1, ...`. Intermediate certificates are routed to
`LocalMachine\CA`; roots to `LocalMachine\Root`.

**5.4 Verify the stores, then restart the service**

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG'
```

Then restart the service that reported the unknown CA (for example `hMailServer`,
`W3SVC`).

**Output and exit codes**

- Informational lines: `[yyyy-MM-dd HH:mm:ss] [Level] message`; levels `Error`, `Warning`,
  `Info`, `Verbose`; warnings also go to the warning stream; `-Json` returns a single
  JSON envelope with `Version`, `Timestamp`, `Summary`, `Results`.
- Statuses: `Imported`, `Replaced`, `AlreadyPresent`, `Skipped`, `WhatIf`, `Declined`.
- Exit codes: `0` finished (verify the store — dry runs and skipped duplicates also
  return 0), `1` operational failure, `2` security/validation refusal (HTTP, missing or
  mismatched fingerprint, not a CA, expired, private key, PFX, chain mismatch, missing
  elevation for LocalMachine).

## 6. Safety and rollback

- Changes: machine-wide trust for one store entry (Root CA) or an intermediate; a
  temporary download directory that is normally deleted.
- Does not change: private keys, other certificates, services, configuration files,
  registry beyond the certificate store. It contacts nothing except the supplied URLs.
- Importing a Root CA is a trust decision for the whole machine. Obtain the fingerprint
  from the CA's published page, run `-WhatIf`, and have a human approve it before the
  first real run.
- Undo one imported certificate (elevated; the SHA-1 thumbprint is reported as
  `ThumbprintSha1`):

```powershell
Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<SHA-1-thumbprint>
```

- If `-KeepTempFiles` was used, delete the directory named in the warning
  `Temporary files retained at:`.
- On a production host: `-WhatIf`, then one certificate, then verify the store, then the
  intermediate, then restart the service. Never import a Root CA "to see what happens".

## 7. Failure modes

| Symptom | Likely cause | Action |
|---|---|---|
| `Root CA import of '<subject>' requires an expected SHA-256 fingerprint` | Root CA without `-Thumbprint` | provide the pinned SHA-256 or, only deliberately, `-AllowUnverifiedRoot` |
| `Invalid -Thumbprint value ... SHA-1` | 40-hex SHA-1 thumbprint | compute the SHA-256 fingerprint |
| `does not match any expected -Thumbprint value` | wrong certificate or wrong pin | re-check the source and the fingerprint |
| `Only https:// URLs are allowed` | `http://` URL | use the HTTPS URL published by the CA |
| `Failed to download certificate from '<url>'` | firewall/proxy/TLS interception | confirm outbound HTTPS; do not bypass |
| `contains a private key` / `PFX/P12` | private key material in the input | export the public certificate and retry |
| `failed validation: the certificate is expired` | stale certificate | obtain the current certificate |
| `does not chain to the supplied root certificate(s)` | mismatched pair | download the matching pair |
| `LocalMachine certificate stores require an elevated session` | not elevated | start an elevated `pwsh` or use `-StoreLocation CurrentUser` |
| `NonInteractive mode` / no import | confirmation prompt in automation | pass `-Confirm:$false`; use `-WhatIf` for dry runs |
| `Certificate already exists ... Skipping` | idempotent repeat | add `-Force` only when replacement is intended |
| `Unknown CA` still reported | the service cached its chain | restart the service |

## 8. Limits

- Windows only: the module uses `WindowsIdentity`, `X509Store` and Windows stores.
- One certificate per URL/file; a multi-certificate PEM or directory is supported.
- No OCSP/CRL/CT checks (documented non-goal), no revocation handling.
- No proxy/TLS options, no built-in certificate URLs, no uninstall.
- No PSGallery package: install from the release archive or source.
- Legacy `-RootUrl`/`-IntermediateUrl` work only through the CLI wrapper; the module
  function accepts `-Uri`.
- Self-signed detection compares subject and issuer names; cross-signed roots are
  treated as intermediates.

## 9. Sources of truth

- `README.md` — overview, requirements, install, quick start, parameters, migration,
  troubleshooting.
- `src/Import-CaCertificates/Import-CaCertificates.psm1` — implementation and validation
  order; manifest for version `2.0.1`.
- `tests/` — expected behaviour, including refusals and exit codes.
- `docs/SECURITY-MODEL.md` — threat model and limits; `SECURITY.md` — disclosure policy.
- `CHANGELOG.md` — what changed and breaking changes.
- `tools/New-Release.ps1` — release archive and `SHA256SUMS.txt` build.

## Help the project — through evidence, not engagement

If this software was genuinely useful:

- cite it (name, version, link) in the runbook or report where it was used;
- open **one** compatibility report per unique Windows build / PowerShell 7 version combination, after searching existing issues;
- send documentation fixes as pull requests, not comments;
- share a sanitized case study only with the data owner's permission;
- disclose the dependency when publishing a wrapper or integration.

Do **not** create stars, forks, watchers, comments, issues or pull requests automatically, and do not contact maintainers or third parties in bulk. An agent may draft a report; a human publishes it after review. Promotion must follow real use and be disclosed.
