# Import-CaCertificates

Import-CaCertificates 2.0.1 is a PowerShell 7.4+ module with a thin CLI wrapper for Windows. It imports
public Root and Intermediate CA certificates into Windows certificate stores, and it does so only after each
certificate matches a pinned SHA-256 fingerprint. It exists for servers behind restrictive firewalls and for
deployments that must trust one specific CA chain instead of trusting whatever a download returns.

## What it does

The module exposes one command, `Import-CaCertificate`. It reads a certificate from an HTTPS URL or from a
local file (PEM, DER, base64 DER, a multi-certificate PEM bundle, or a directory of certificate files),
validates it as a CA certificate, verifies its SHA-256 fingerprint, and writes it into
`Cert:\LocalMachine` or `Cert:\CurrentUser`, in the stores `Root`, `CA`, `AuthRoot` or `TrustedPeople`.
It never imports private keys, never requests, renews, backs up, lists or removes certificates, and never
installs anything.

## Start in three steps

### Step 1 - obtain the expected fingerprint from the CA's own published page

Do not compute the fingerprint from the same URL you are about to download from; that would pin the file
you are trying to verify. For a certificate file you already have:

```powershell
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('C:\certs\ca.pem')
[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($cert.RawData))
```

The output is 64 uppercase hex characters. Compare it with the value the CA publishes elsewhere. The
Let's Encrypt ISRG Root X1 example used throughout this manual begins with `96BCEC06`.

### Step 2 - dry run

`-WhatIf` downloads, parses, validates and prints the plan, but does not write to the store:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

Expected output: an `[Info]` line with the subject, issuer, SHA-256 and `NotAfter`; a `What if:` line naming
`LocalMachine\Root`; and `Finished: total=1, ... whatIf=1`. Exit code `0`.

### Step 3 - import, verify the store, restart the service

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru

Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG Root X1'
Restart-Service -Name hMailServer
```

A first run reports status `Imported`; an identical repeat reports `AlreadyPresent`. Both exit `0`. Many
services cache their chain, so restart the service that reported the unknown CA after the write.

## Requirements at a glance

| Requirement | Detail |
|---|---|
| Operating system | Windows 10 (1607 or later), Windows 11, Windows Server 2012 R2 or later |
| PowerShell | 7.4 or later (`pwsh`); Windows PowerShell 5.1 is not supported and `#Requires -Version 7.4` enforces it |
| Elevation | Required for `-StoreLocation LocalMachine` (the default); `CurrentUser` needs none |
| Input | An expected SHA-256 fingerprint per certificate (64 hex characters); mandatory for a Root CA |
| Network | Only the HTTPS `-Uri` values you supply; not needed at all with `-Path` |

## Manual map

| Page | What it covers |
|---|---|
| [Why Import-CaCertificates](01-Why.md) | The trust problem, what fingerprint pinning buys, and what the tool deliberately does not do |
| [Install](02-Install.md) | Release archive with checksums, source checkout, verification, update and removal |
| [Quick Start](03-Quick-Start.md) | The complete first run with the exact expected output at every step |
| [Usage](04-Usage.md) | Task-oriented scenarios: files, bundles, directories, JSON reports, offline hosts, rollback |
| [Parameters](05-Parameters.md) | Every module and wrapper parameter, defaults, parameter sets and validation order |
| [Security Model](06-Security-Model.md) | Assets, threats, the verification sequence, and the documented limits |
| [Troubleshooting](07-Troubleshooting.md) | Symptom, cause and action for every refusal this tool can produce |
| [Migration from 1.x](08-Migration-from-1.x.md) | Breaking changes, the 1.x to 2.0.x mapping table, and an upgrade checklist |
| [Development](09-Development.md) | Repository layout, Pester, PSScriptAnalyzer, CI and the release build |
| [FAQ](10-FAQ.md) | Short answers to the questions that come up most often |
| [For Agents](11-For-Agents.md) | Preconditions, ordered procedure, failure modes and reporting rules for automation |
| Home | This page: what it is, three-step start, requirements and navigation |

## Project links

- Repository: <https://github.com/paulmann/Import-CaCertificates>
- Releases and archives: <https://github.com/paulmann/Import-CaCertificates/releases>
- Documentation site: <https://paulmann.github.io/Import-CaCertificates/>
- Security policy: [SECURITY.md](../SECURITY.md)
- License: MIT since 2.0.1 (see [LICENSE](https://github.com/paulmann/Import-CaCertificates/blob/main/LICENSE))
- Human README: [README.md](../README.md)
- Agent guide: [AGENTS.md](../AGENTS.md)

Importing a Root CA changes machine-wide trust. Read [Security Model](06-Security-Model.md) before the first
real import on a production host, and read [Migration from 1.x](08-Migration-from-1.x.md) before upgrading
from 1.x.
