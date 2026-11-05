# FAQ

Short answers to the questions that come up most often. Each answer links to the chapter that explains it in
full.

## Does it need administrator rights?

Only for the default `-StoreLocation LocalMachine`. Start an elevated `pwsh` for machine-wide trust, or pass
`-StoreLocation CurrentUser` to write into the current user's profile without elevation. A `LocalMachine`
run without elevation is refused with exit code `2`, never silently redirected. See
[Quick Start](03-Quick-Start.md) and [Troubleshooting](07-Troubleshooting.md).

## Which platforms and PowerShell versions are supported?

Windows 10 (1607 or later), Windows 11 and Windows Server 2012 R2 or later with PowerShell 7.4 or later
(`pwsh`). Windows PowerShell 5.1 is not supported, and `#Requires -Version 7.4` enforces the floor. Windows 7
and Windows 8.1 are unsupported because PowerShell 7 does not install there. See [Install](02-Install.md).

## Does it work without internet access?

Yes, with `-Path`. The tool contacts nothing except the `-Uri` values you pass, so an air-gapped host can
import a certificate file that was fetched and verified elsewhere. See
[Offline / air-gapped host](04-Usage.md#offline--air-gapped-host).

## How does it decide between the Root and CA stores?

A certificate is treated as self-signed when its subject and issuer distinguished names are identical. A
self-signed CA goes to `Root`; a non-self-signed CA goes to `CA`. An explicit `-StoreName` overrides the
routing. A cross-signed root has a different issuer and is therefore treated as an intermediate, which is
where it belongs. See [Parameters](05-Parameters.md#store-routing).

## Why does it refuse my PFX or P12 file?

Because a PFX/P12 container may carry a private key, and this tool imports public certificates only. Export
the public certificate (`Export-Certificate -Type CERT`) and import that file. A PEM file with a
`PRIVATE KEY` block is refused for the same reason. See [Security Model](06-Security-Model.md).

## Can I import an expired certificate, or use -Force to get past it?

No. `-Force` replaces an entry with the same SHA-256 fingerprint; it does not relax validation. An expired
certificate is refused before any store write. Obtain the current certificate from the CA. See
[Parameters](05-Parameters.md#force-is-not-a-bypass).

## What does "does not chain to the supplied root certificate(s)" mean?

You supplied a root and an intermediate in the same batch, and the intermediate does not validate against
that root. Download the matching pair, or import only the certificate you need. `-SkipChainValidation` opts
out only when you accept that the pair is not meant to chain. See [Troubleshooting](07-Troubleshooting.md).

## Is running the import twice a problem?

No. A certificate with the same SHA-256 fingerprint is detected and reported as `AlreadyPresent`; nothing
is written and the exit code is `0`. This is what makes the tool safe for scheduled tasks. See
[Quick Start](03-Quick-Start.md#step-6---confirm-idempotence).

## How do I undo an import?

Remove the SHA-1 thumbprint reported in the result object:

```powershell
$result = Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' -Confirm:$false -PassThru
Remove-Item -Path "Cert:\LocalMachine\Root\$($result.ThumbprintSha1)"
```

Restart the dependent service afterwards. See [Usage](04-Usage.md#undo-an-import).

## Why is the SHA-256 fingerprint the identity check instead of the SHA-1 thumbprint?

SHA-256 is collision-resistant and is what the tool pins; the SHA-1 thumbprint is reported only because
`certmgr.msc` and `certutil` address certificates with it. A 40-hex value passed to `-Thumbprint` is
recognised as SHA-1 and refused with an explanatory message. See [Security Model](06-Security-Model.md).

## Why is the fingerprint not the same as Get-FileHash of the PEM file?

`-Thumbprint` is the SHA-256 of the certificate's DER encoding (`X509Certificate2.RawData`), not of the file
bytes. A PEM file wraps the DER in base64 text, so its file hash differs. Compute the certificate hash from
`RawData`, as the [Quick Start](03-Quick-Start.md) shows.

## Does it install a service, an agent or telemetry?

No. There is no installer, no service, no scheduled task, no configuration file, no environment variable and
no telemetry. The release is an extracted directory; the only network requests are the `-Uri` values you
supply. See [Install](02-Install.md).

## Does it run on Linux or macOS?

No. The module uses `WindowsIdentity`, `X509Store` and the Windows certificate stores, and it refuses to run
off Windows with exit code `2`. Use the platform's own trust-store tooling on other systems.

## Does exit code 0 mean the certificate was imported?

Not necessarily. Exit code `0` means the run finished, and that includes a `WhatIf` dry run, an
`AlreadyPresent` duplicate, a `Skipped` root and a `Declined` confirmation. Check the status in the output or
in the `-PassThru`/`-Json` result, and verify the store if the import mattered. See
[Import results and exit codes](03-Quick-Start.md#statuses-and-exit-codes-after-the-run).

## Why must automation pass -Confirm:$false?

The command declares `ConfirmImpact = 'High'`, because importing a Root CA changes machine-wide trust. An
interactive session is asked before each write; a non-interactive session cannot answer and fails instead of
writing. Automation must pass `-Confirm:$false` explicitly. See [Parameters](05-Parameters.md).

## Can it import a non-CA certificate?

Only with an explicit `-StoreName TrustedPeople`, which is explicit trust for a peer, not a CA anchor.
Automatic routing and the CA stores refuse a non-CA certificate. See
[Usage](04-Usage.md#trust-a-specific-end-entity-certificate).

## Can it remove or list certificates?

No. It imports; it does not manage the store. Use `Get-ChildItem Cert:\...` to list and `Remove-Item` to
remove. See [Install](02-Install.md#remove).

## What happens to downloaded files?

They go into a unique `CaImport_<12 hex>` directory under `-TempPath` (default `$env:TEMP`) and the directory
is removed after the run. `-KeepTempFiles` keeps it and prints the path; delete it yourself. Existing files
in `-TempPath` are never deleted. See [Parameters](05-Parameters.md#temporary-files).

## Does it support proxies or custom TLS settings?

There are no proxy or TLS parameters: the download uses the PowerShell/.NET defaults of the session. If the
host needs a proxy or inspects TLS, configure that at the system or session level. A failed download is an
operational error (exit `1`), not a reason to relax the HTTPS rule. See
[Troubleshooting](07-Troubleshooting.md#download-and-network).

## What is new in 2.0.1?

2.0.1 relicenses the project under the MIT License. No code, behaviour or API changes; 2.0.0 is the
security-focused rewrite. See [Migration from 1.x](08-Migration-from-1.x.md).

## Where does the documentation come from?

The human README is the project overview; this wiki is the manual and is generated from the `wiki/`
directory in the repository; the documentation site publishes the same reference as a browsable site. The
sources of truth are listed at the end of [For Agents](11-For-Agents.md#sources-of-truth).
