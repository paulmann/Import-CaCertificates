# Quick Start

This chapter is the complete first run: from "the tool is not installed" to "the store contains the
certificate and the dependent service is running". Every step shows the command and the shape of the
expected output, so a missing line tells you where the run diverged.

The example throughout is the Let's Encrypt ISRG Root X1 certificate. Its SHA-256 fingerprint,
`96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6`, is published by Let's Encrypt and is
used here as a working example, not as a recommendation to trust any particular CA.

## Step 1 - prepare an elevated session for LocalMachine

`-StoreLocation LocalMachine` is the default and requires administrator rights. Start an elevated
`pwsh`, or add `-StoreLocation CurrentUser` to every command if the trust should apply to one user profile
only. Installation does not need elevation.

```powershell
$PSVersionTable.PSVersion
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

Expected: a version of `7.4` or later and `True`. See [Install](02-Install.md) for the archive steps.

## Step 2 - dry run

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

Expected output has three recognisable parts:

```text
[<timestamp>] [Info] Import-CaCertificate 2.0.1 started: 1 source(s), target LocalMachine\<auto>.
[<timestamp>] [Info] Certificate: Subject='CN=ISRG Root X1, O=Internet Security Research Group, C=US',
    Issuer='CN=ISRG Root X1, O=Internet Security Research Group, C=US', SHA-256=96BCEC06...,
    NotAfter=2035-06-04 11:04:38Z
What if: Performing the operation "Import certificate 'CN=ISRG Root X1, ...' (SHA-256 96BCEC06...)"
    on target "LocalMachine\Root".
[<timestamp>] [Info] Finished: total=1, imported=0, replaced=0, alreadyPresent=0, skipped=0, declined=0,
    whatIf=1.
```

The certificate was downloaded, parsed, validated and fingerprint-checked; nothing was written. The
`What if:` line names the target store the tool chose automatically (`Root` for a self-signed CA).

## Step 3 - import

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru
```

Expected on the first run: the same `[Info]` certificate line, then `Imported into 'LocalMachine\Root'
(SHA-256 96BCEC06...)`, then `Finished: total=1, imported=1, ...`. The result object returned by `-PassThru`
has `Status = 'Imported'`, `StoreLocation = 'LocalMachine'`, `StoreName = 'Root'`, `IsCA = True`,
`IsSelfSigned = True` and both thumbprints.

Without `-Confirm:$false` an interactive session prompts, because the command declares
`ConfirmImpact = 'High'`. Automation must pass `-Confirm:$false`; a run that hits the prompt in a
non-interactive session fails instead of writing.

## Step 4 - verify the store

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG Root X1'
```

Expected: one certificate object; its `Thumbprint` is the SHA-1 thumbprint used by `certmgr.msc`. The
SHA-256 identity value is not a property of `X509Certificate2`; compare it with a fresh hash of `RawData` if
you need proof. More verification tools are in [Troubleshooting](07-Troubleshooting.md).

## Step 5 - restart the dependent service

Many services read the machine trust store once at start-up and cache the chain. If the original symptom
was `Unknown CA` from hMailServer, Exim, IIS or another service, restart it:

```powershell
Restart-Service -Name hMailServer
# or
Restart-Service -Name W3SVC
```

A successful import does not prove the application now trusts the chain; the restart and a real request do.

## Step 6 - confirm idempotence

Run the same import again. Expected: status `AlreadyPresent`, `Finished: total=1, imported=0, ...
alreadyPresent=1`, exit code `0`. A certificate with the same SHA-256 fingerprint is never duplicated.

Add `-Force` only when you deliberately want to replace an existing copy of the same certificate; `-Force`
replaces the existing entry but never skips validation or fingerprint matching.

## Statuses and exit codes after the run

| Status | Meaning |
|---|---|
| `Imported` | Written to the target store and read back successfully |
| `Replaced` | An existing copy with the same SHA-256 fingerprint was replaced (`-Force`) |
| `AlreadyPresent` | The same certificate is already in the store; nothing was written |
| `Skipped` | Excluded by policy (`-NoRootImport`) |
| `WhatIf` | Passed all checks, but the dry run did not write |
| `Declined` | The interactive confirmation (`-RequireConfirmation`) was answered "no" |

| Exit code | Meaning |
|---|---|
| `0` | The run finished, including dry runs, skipped duplicates and declined confirmations; verify the store before treating it as "imported" |
| `1` | Operational failure: download, file system, store access, module not found |
| `2` | Security or validation refusal: HTTP, missing or failed fingerprint, not a CA, expired, private key, PFX, chain mismatch, no elevation for `LocalMachine` |

## If something did not work

- The command printed a refusal: [Troubleshooting](07-Troubleshooting.md) maps every message to a cause.
- You are coming from 1.x and the parameters changed: [Migration from 1.x](08-Migration-from-1.x.md).
- You want more scenarios than this happy path: [Usage](04-Usage.md).
- You want to know why the fingerprint is the identity check: [Security Model](06-Security-Model.md) and the
  [FAQ](10-FAQ.md).
