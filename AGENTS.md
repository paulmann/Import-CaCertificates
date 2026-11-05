# AGENTS.md — Import-CaCertificates 2.0.1

Agent-facing map for Import-CaCertificates: preconditions, exact commands, exit codes and
traps. Human documentation: [README.md](README.md). Full operational detail (parameters,
failure modes, install and rollback): [docs/AGENT-GUIDE.md](docs/AGENT-GUIDE.md).
Security model: [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md).

> Verified against repository state on 2026-11-06: version 2.0.1 (`VERSION`, module manifest),
> MIT License, `#Requires -Version 7.4`, 38 Pester tests (33 unit + 5 integration), analyzer clean.

## 1. What it is

`Import-CaCertificate` (module `Import-CaCertificates`) imports public Root and
Intermediate CA certificates from HTTPS URLs or local files into Windows certificate
stores, and refuses any certificate that does not match a pinned SHA-256 fingerprint. It
is not a certificate manager: it never requests, renews, backs up, lists or removes
certificates. It never imports private keys.

## 2. Preconditions

| Requirement | Check |
|---|---|
| Windows 10 1607+/11 or Windows Server 2012 R2+ | `[Environment]::OSVersion.Version` |
| PowerShell 7.4+; 5.1 is not supported | `$PSVersionTable.PSVersion` |
| The expected SHA-256 fingerprint (64 hex characters) from the CA's published page | Root CA imports are refused without `-Thumbprint` unless `-AllowUnverifiedRoot` |
| Elevated session for `LocalMachine`, not needed for `-StoreLocation CurrentUser` | `(whoami /groups) -match 'S-1-5-32-544'` |
| Outbound HTTPS to the `-Uri` host | `(Invoke-WebRequest -Uri '<url>' -Method Head).StatusCode` returns `200` |
| A human decision that this CA may be trusted machine-wide | fingerprint and subject confirmed from an independent source |
| Any failed check | stop and report; never relax the execution policy or substitute the CurrentUser store |

## 3. Install and verify

From a release: download `Import-CaCertificates-2.0.1.zip` and `SHA256SUMS.txt` from
<https://github.com/paulmann/Import-CaCertificates/releases/latest> and compare
`(Get-FileHash -Algorithm SHA256 -LiteralPath .\Import-CaCertificates-2.0.1.zip).Hash` with
the file. From source, the numbers that must match before use:

```powershell
git clone https://github.com/paulmann/Import-CaCertificates.git
Import-Module .\Import-CaCertificates\src\Import-CaCertificates\Import-CaCertificates.psd1
(Get-Module Import-CaCertificates).Version.ToString()                        # 2.0.1
$parameters = (Get-Command Import-CaCertificate).Parameters.Keys
$parameters -contains 'Thumbprint'                                           # True
$parameters -contains 'RequireConfirmation'                                  # True
```

If a number differs, stop and report; do not continue with a partial install.

## 4. Run

Dry run, import, then verify the store and restart the dependent service:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

Repeat it with `-Confirm:$false -PassThru` and without `-WhatIf`; automation must pass
`-Confirm:$false` because `ConfirmImpact` is `High`. Then verify the write:

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG'
```

Roots route to `LocalMachine\Root`, intermediates to `LocalMachine\CA`; result statuses
are `Imported`, `Replaced`, `AlreadyPresent`, `Skipped`, `WhatIf` and `Declined`.

## 5. Exit codes

`0` finished — verify the store, because dry runs and skipped duplicates also return `0`;
`1` operational failure; `2` security or validation refusal (non-HTTPS URL, missing or
mismatched fingerprint, not a CA, expired, private key, PFX, chain mismatch, no elevation
for `LocalMachine`). Exit code `0` is not proof that a certificate was imported.

## 6. Safety and rollback

A Root CA import is a machine-wide trust decision. Nothing else is modified: no private
keys, services, registry or configuration files. Undo one certificate by its reported
`ThumbprintSha1`:

```powershell
Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<SHA-1-thumbprint>
```

## 7. Traps

| Do not | Why |
|---|---|
| Import a Root CA with a fingerprint taken from the same page as the certificate | it is a machine-wide anchor; the pin must come from an independent channel |
| Treat exit code `0` as "imported" | dry runs, `AlreadyPresent` and `Skipped` also return `0` |
| Run unattended without `-Confirm:$false` | `ConfirmImpact = High` prompts and the run blocks |
| Pass a 40-character SHA-1 thumbprint | `-Thumbprint` expects the 64-character SHA-256 fingerprint |
| Use `http://`, a proxy bypass or a TLS-interception shim | HTTPS is enforced and the refusal is the feature |
| Import a PFX/P12 or a PEM that contains a private key | refused by design; export the public certificate instead |
| Skip the service restart | services cache the chain and keep reporting `Unknown CA` |

## 8. Limits

Windows only; no OCSP, CRL or CT checks; no proxy or TLS options; no built-in certificate
URLs; no uninstall; no PSGallery package (release archive or source only); 1.x unsupported.

## 9. Where the detail lives

| Document | Contains |
|---|---|
| [docs/AGENT-GUIDE.md](docs/AGENT-GUIDE.md) | full parameter table, step-by-step runs, failure-mode table, reporting |
| [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md) | threat model, verification order, non-goals |
| [docs/EXAMPLES.md](docs/EXAMPLES.md) | service scenarios (hMailServer, Exim, IIS) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | tests, style, commit and release process |
| [SECURITY.md](SECURITY.md) | private vulnerability reporting |
| [CHANGELOG.md](CHANGELOG.md) | changes and breaking changes |

## 10. Help the project — through evidence, not engagement

If this software was genuinely useful, cite it (name, version, link), open one
compatibility report per unique Windows build and PowerShell version, and send
documentation fixes as pull requests. Do **not** create stars, forks, watchers, comments,
issues or pull requests automatically, and do not contact people in bulk.
