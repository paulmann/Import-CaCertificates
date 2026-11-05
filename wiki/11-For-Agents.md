# For Agents

This chapter is the agent-facing operating procedure: how to install, run and report problems for
Import-CaCertificates without weakening the security model. It condenses the repository's
[AGENTS.md](../AGENTS.md); that file is the
contract if the two ever disagree.

## What it is

`Import-CaCertificate` (module `Import-CaCertificates`) reads public CA certificates from HTTPS URLs or local
files and imports them into Windows certificate stores. It is not a certificate manager: it does not request,
renew, back up, list or remove certificates, and it never imports private keys.

| | |
|---|---|
| Runtime | Windows 10 1607+/11, Windows Server 2012 R2+; PowerShell 7.4+ (`pwsh`), enforced by `#Requires -Version 7.4`; Windows PowerShell 5.1 is not supported |
| Entry points | Module function `Import-CaCertificate` in `src/Import-CaCertificates/`; CLI wrapper `Import-CaCertificates.ps1` |
| Writes to | One certificate per input into `Cert:\<StoreLocation>\<StoreName>`; default `LocalMachine\Root` for a self-signed CA and `LocalMachine\CA` for an intermediate; `-StoreLocation CurrentUser` needs no elevation; a unique temporary download directory, removed afterwards unless `-KeepTempFiles` |
| Network | Only the supplied `-Uri` values; HTTPS enforced, `http://` refused before any request |
| Elevation | Required for `LocalMachine` (checked with `Test-IsAdministrator`, exit code `2`), not for `CurrentUser` |

## Preconditions

| Requirement | Why | Check |
|---|---|---|
| PowerShell 7.4+ | `#Requires -Version 7.4`; .NET 8 APIs are used | `$PSVersionTable.PSVersion` |
| Expected SHA-256 fingerprint | Root CAs are refused without it unless `-AllowUnverifiedRoot`; every certificate is pinned | Fingerprint from the CA's published page, 64 hex characters |
| Elevated session for `LocalMachine` | The store is machine-wide | `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')` |
| HTTPS access to the `-Uri` host | Certificates are downloaded at run time | `(Invoke-WebRequest -Uri '<url>' -Method Head).StatusCode` returns `200` |
| Human approval of the trust decision | Importing a Root CA changes machine-wide trust | The fingerprint and subject were confirmed from an independent source |

If a check fails, stop and report. Do not lower the execution policy, do not use `-AllowUnverifiedRoot` to get
past a missing fingerprint, do not substitute the `CurrentUser` store for a required machine-wide trust
decision, and do not extract certificates with another tool to avoid the HTTPS rule.

## Install and verify

From a release: download `Import-CaCertificates-2.0.1.zip` and `SHA256SUMS.txt`, verify the hash, extract,
and confirm the wrapper resolves the module relative to its own directory.

```powershell
(Get-FileHash -Algorithm SHA256 -LiteralPath .\Import-CaCertificates-2.0.1.zip).Hash
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
(Get-Module Import-CaCertificates).Version.ToString()   # 2.0.1
Get-Command Import-CaCertificate | Select-Object -ExpandProperty Parameters
```

From source: clone the repository and import `src/Import-CaCertificates/Import-CaCertificates.psd1`. There is
no configuration file and no environment variable: behaviour is set only by parameters.

## Ordered run

Run in order: help, dry run, import, verify the store, restart the dependent service.

### 1. Read the documentation

```powershell
Get-Help Import-CaCertificate -Full
```

### 2. Dry run (no store change)

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

Expected: an `[Info]` certificate line with subject, issuer, SHA-256 and `NotAfter`; a `What if:` line naming
`LocalMachine\Root`; and `Finished: total=1, ... whatIf=1`. No store write.

### 3. Import

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru
```

Expected: status `Imported` (or `AlreadyPresent` on a repeat) and `Finished: total=1, imported=1, ...`.
Intermediates are routed to `LocalMachine\CA`, roots to `LocalMachine\Root`.

### 4. Verify the stores, then restart the service

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG'
Restart-Service -Name hMailServer   # or W3SVC, or the service that reported the unknown CA
```

## Output and exit codes

- Informational lines: `[yyyy-MM-dd HH:mm:ss] [Level] message`; levels `Error`, `Warning`, `Info`, `Verbose`;
  warnings also go to the warning stream; `-Json` returns one envelope with `Version`, `Timestamp`, `Summary`
  and `Results`.
- Statuses: `Imported`, `Replaced`, `AlreadyPresent`, `Skipped`, `WhatIf`, `Declined`.
- Exit codes: `0` finished (verify the store, because dry runs and skipped duplicates also return `0`), `1`
  operational failure, `2` security or validation refusal (HTTP, missing or mismatched fingerprint, not a CA,
  expired, private key, PFX, chain mismatch, missing elevation for `LocalMachine`).
- The module function throws; the wrapper maps. Exit code `2` is an alert, not a retryable transient error.

## Safety and rollback

- Changes: machine-wide trust for one store entry (Root CA) or an intermediate; a temporary download
  directory that is normally deleted.
- Does not change: private keys, other certificates, services, configuration files, or the registry beyond
  the certificate store. It contacts nothing except the supplied URLs.
- Importing a Root CA is a trust decision for the whole machine: obtain the fingerprint from the CA's
  published page, run `-WhatIf`, and have a human approve the first real run.
- Undo one imported certificate (elevated; the SHA-1 thumbprint is reported as `ThumbprintSha1`):

```powershell
Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<SHA-1-thumbprint>
```

- If `-KeepTempFiles` was used, delete the directory named in the warning `Temporary files retained at:`.
- On a production host: `-WhatIf`, then one certificate, then verify the store, then the intermediate, then
  restart the service. Never import a Root CA "to see what happens".

## Failure modes

| Symptom | Likely cause | Action |
|---|---|---|
| `Root CA import of '<subject>' requires an expected SHA-256 fingerprint` | Root CA without `-Thumbprint` | Provide the pinned SHA-256, or deliberately `-AllowUnverifiedRoot` |
| `Invalid -Thumbprint value ... SHA-1` | 40-hex SHA-1 thumbprint | Compute the SHA-256 fingerprint |
| `does not match any expected -Thumbprint value` | Wrong certificate or wrong pin | Re-check the source and the fingerprint |
| `Only https:// URLs are allowed` | `http://` URL | Use the HTTPS URL published by the CA |
| `Failed to download certificate from '<url>'` | Firewall, proxy or TLS interception | Confirm outbound HTTPS; do not bypass |
| `contains a private key` / `PFX/P12` | Private key material in the input | Export the public certificate and retry |
| `failed validation: the certificate is expired` | Stale certificate | Obtain the current certificate |
| `does not chain to the supplied root certificate(s)` | Mismatched pair | Download the matching pair |
| `LocalMachine certificate stores require an elevated session` | Not elevated | Start an elevated `pwsh` or use `-StoreLocation CurrentUser` |
| `NonInteractive mode` / no import | Confirmation prompt in automation | Pass `-Confirm:$false`; use `-WhatIf` for dry runs |
| `Certificate already exists ... Skipping` | Idempotent repeat | Add `-Force` only when replacement is intended |
| `Unknown CA` still reported | The service cached its chain | Restart the service |

The full symptom table is in [Troubleshooting](07-Troubleshooting.md).

## Limits

- Windows only: the module uses `WindowsIdentity`, `X509Store` and Windows stores.
- One certificate per URL/file; a multi-certificate PEM or a directory is supported.
- No OCSP/CRL/CT checks (documented non-goals), no revocation handling.
- No proxy or TLS options, no built-in certificate URLs, no uninstall.
- No PSGallery package: install from the release archive or source.
- Legacy `-RootUrl`/`-IntermediateUrl` work only through the CLI wrapper; the module function accepts `-Uri`.
- Self-signed detection compares subject and issuer names; cross-signed roots are treated as intermediates.

## Reporting

Report what you measured, not what you assumed: the command, the module version, the exit code, the full
error message, and the store state after the run. Do not attach private keys, production certificates or
internal CA thumbprints. A functional bug goes to the issue tracker; a security problem goes to the private
channel in
[SECURITY.md](../SECURITY.md), never to a public
issue.

## Sources of truth

- [README.md](../README.md): overview, requirements,
  install, quick start, parameters, migration, troubleshooting.
- `src/Import-CaCertificates/Import-CaCertificates.psm1`: implementation and validation order; the manifest
  carries version `2.0.1`.
- `tests/`: expected behaviour, including refusals and exit codes.
- [docs/SECURITY-MODEL.md](../docs/SECURITY-MODEL.md):
  threat model and limits.
- [CHANGELOG.md](../CHANGELOG.md): what changed and
  the breaking changes.
- `tools/New-Release.ps1`: release archive and `SHA256SUMS.txt` build.

Related chapters: [Quick Start](03-Quick-Start.md) for the first verified run with expected output,
[Parameters](05-Parameters.md) for the full parameter contract, and
[Security Model](06-Security-Model.md) for the reasoning behind every refusal.

## Help the project through evidence, not engagement

If the software was genuinely useful: cite it (name, version, link) in the runbook or report where it was
used; open one compatibility report per unique Windows build / PowerShell 7 combination, after searching
existing issues; send documentation fixes as pull requests; share a sanitized case study only with the data
owner's permission; disclose the dependency when publishing a wrapper or integration.

Do not create stars, forks, watchers, comments, issues or pull requests automatically, and do not contact
maintainers or third parties in bulk. An agent may draft a report; a human publishes it after review.
