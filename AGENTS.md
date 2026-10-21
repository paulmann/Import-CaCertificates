# AGENTS.md — Import-CaCertificates 1.0.0

Agent-facing guide: how to install Import-CaCertificates, run it, and report problems responsibly.
Human documentation: [README.md](README.md).

> Verified against repository state on 2026-10-22. Version covered: 1.0.0 (README version badge;
> no VERSION file, no manifest, no version string in the script). Branch `main`, commit `7c24c8e`,
> no tags and no releases.

## 1. What it is

`Import-CaCertificates.ps1` downloads one Root CA certificate and, optionally, one Intermediate CA
certificate from HTTPS URLs and imports them into the Windows Local Machine certificate stores
(`LocalMachine\Root` and `LocalMachine\CA`). It serves servers behind restrictive firewalls and
deployments that must trust a specific CA chain (for example the chain behind hMailServer, Exim or
IIS). It is not a certificate manager: it does not request, renew, back up, list or remove
certificates, and it never touches the Current User stores.

| | |
|---|---|
| Runtime / platform | Windows 7 / Windows Server 2012 R2 or later (README section 3); PowerShell 7.5 or higher, enforced by `#Requires -Version 7.5` |
| Entry point | `Import-CaCertificates.ps1` - one script, no module, no installer, no dependencies |
| Writes to | `Cert:\LocalMachine\Root` (Root CA) and `Cert:\LocalMachine\CA` (Intermediate CA); a temporary directory, default `$env:TEMP\CaImport_<8 hex characters>`, deleted afterwards unless `-KeepTempFiles` is used |
| Network access | Downloads only the URLs passed in `-RootUrl` and `-IntermediateUrl`; HTTPS is enforced and any other scheme is rejected before the request is made |
| Elevation | Required: `#Requires -RunAsAdministrator`, plus an inner administrator check that exits 1 |

## 2. Preconditions

| Requirement | Why | Check |
|---|---|---|
| Elevated session | the script writes to `LocalMachine` stores | `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)` returns `True` |
| PowerShell 7.5+ | `#Requires -Version 7.5` refuses to start otherwise | `$PSVersionTable.PSVersion` |
| Execution policy allows the script | README section 5 asks for `RemoteSigned` | `Get-ExecutionPolicy` |
| Both URLs use `https://` | the download helper throws on any other scheme | inspect the URL; `$url -like 'https://*'` |
| Outbound HTTPS to the CA host | the certificate is fetched at run time | `(Invoke-WebRequest -Uri '<certificate-url>' -Method Head).StatusCode` returns `200` |
| A human-approved CA | importing a Root CA changes machine-wide trust | the expected subject and thumbprint come from the CA's own published page |

If a check fails, stop and report. Do not lower the execution policy, do not substitute the Current
User store, and do not extract certificates with another tool to avoid the HTTPS rule.

## 3. Install

### 3.1 From a release

Source install only - this repository has no releases.

### 3.2 From source

Download the single script (command as published in README section 4), or clone the repository and
run the script from the clone root:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/paulmann/Import-CaCertificates/main/Import-CaCertificates.ps1" -OutFile "Import-CaCertificates.ps1"
git clone https://github.com/paulmann/Import-CaCertificates.git
```

There is no installation step: no module import, no package manager, nothing to register.

### 3.3 Verify

```powershell
pwsh -NoProfile -Command "Get-Help .\Import-CaCertificates.ps1"
```

Expected output is the syntax line, which is all `Get-Help` returns for this script:

```
Import-CaCertificates.ps1 [-RootUrl] <string> [[-IntermediateUrl] <string>] [[-TempPath] <string>] [-Force] [-KeepTempFiles] [-WhatIf] [-Confirm] [<CommonParameters>]
```

The comment-based help inside the file is not returned by `Get-Help` (it follows the `#Requires` and
`using` statements), so read README section 9 or the comment header at the top of the script.

## 4. Configure

There is no configuration file and no environment variable. Behaviour is set only by parameters:

| Parameter | Type | Required | Meaning |
|---|---|---|---|
| `-RootUrl` | string | yes | HTTPS URL of the Root CA certificate (PEM or DER) |
| `-IntermediateUrl` | string | no | HTTPS URL of the Intermediate CA certificate (PEM or DER) |
| `-TempPath` | string | no | directory for downloaded files; default is a unique subdirectory of the system TEMP folder |
| `-Force` | switch | no | remove an existing certificate with the same thumbprint from that store and add the downloaded one; without it an existing certificate is skipped |
| `-KeepTempFiles` | switch | no | keep the temporary directory and print its path instead of deleting it |
| `-WhatIf` / `-Confirm` | common | no | standard `ShouldProcess` gate; the store write is skipped or confirmed |

README section 8 and section 9 name the retention switch `-KeepFiles`; that parameter does not
exist. The implemented name is `-KeepTempFiles`.

## 5. Use

Run in order: help, dry run, one Root certificate, verify the store, the Intermediate, restart the service.

**5.1 Read the documentation**: `Get-Help .\Import-CaCertificates.ps1` (syntax only) and
`Get-Content .\Import-CaCertificates.ps1 -TotalCount 75` (the comment header with parameter help).

**5.2 Dry run (no store change)**

```powershell
.\Import-CaCertificates.ps1 -RootUrl 'https://letsencrypt.org/certs/isrgrootx1.pem' -WhatIf -Confirm:$false
```

Expected: `[<timestamp>] [Info] Loaded Certificate: Subject='...', Thumbprint='...'` and
`What if: Performing the operation "Import certificate <subject>" on target "LocalMachine\Root".`
`-WhatIf` still downloads the certificate and still deletes the temporary directory; it only skips
the store write.

**5.3 Import a certificate (Root only, then Root plus Intermediate)**

```powershell
.\Import-CaCertificates.ps1 -RootUrl "https://letsencrypt.org/certs/isrgrootx1.pem" -Confirm:$false
.\Import-CaCertificates.ps1 -RootUrl "https://letsencrypt.org/certs/isrg-root-x2.pem" -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-e1.pem" -Confirm:$false
```

Expected after the first: `Successfully imported certificate into 'LocalMachine\Root'.` then
`Certificate import process completed successfully.` In the second, the Root goes to
`LocalMachine\Root` and the Intermediate to `LocalMachine\CA`. Add `-Force` to replace an existing
certificate: the script reports `Certificate exists. Force specified. Re-importing to '<store>'.` and
re-adds the downloaded certificate. Add `-KeepTempFiles` to keep the temporary directory for
debugging; expected: `Temporary files retained at: <path>`.

**5.4 Verify the stores, then restart the service**

The script reports the thumbprint it handled; the certificate provider shows the same stores:

```powershell
Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object Thumbprint -eq '<thumbprint-from-log>'
Get-ChildItem -Path Cert:\LocalMachine\CA | Where-Object Subject -match 'ISRG'
```

README section 10: then restart the service that reported the unknown CA (for example the hMailServer
service) so it re-reads the machine trust store.

**Output and exit codes**

Log lines look like `[yyyy-MM-dd HH:mm:ss] [Level] message`, with levels `Info`, `Warning`, `Error`
and `Verbose`. `Info` messages go to the information stream and are displayed; `-Verbose` adds the
download and cleanup details. Capture them with `6>&1` when parsing.

| Code | Meaning |
|---|---|
| 0 | The run finished. This includes a dry run, a skipped duplicate, and a declined confirmation - a zero exit code does not prove that a certificate was written. Always verify the store. |
| 1 | Explicit `exit 1` on the inner administrator check, and in the outer error handler for any download, parse or store error |
| none | `#Requires -Version 7.5` or `#Requires -RunAsAdministrator` stops the script before its body runs when the check is not met |

## 6. Safety and rollback

- Changes: machine-wide trust for every account on the host (the Root store is authoritative for TLS
  validation), one or two certificates, and a temporary directory that is normally deleted.
- Does not change: `Cert:\CurrentUser\*`, other certificates, registry beyond the certificate stores,
  services, config files, installed software. It contacts nothing except the URLs supplied.
- Importing a Root CA is a trust decision for the whole machine. Obtain the subject and SHA-1
  thumbprint from the CA's published page and have a human confirm them before the first real run.
- Undo one imported certificate (elevated; the thumbprint is in the `Loaded Certificate` and
  `Successfully imported` lines):

```powershell
Remove-Item -Path Cert:\LocalMachine\Root\<thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<thumbprint>
```

  `-Force` removes a certificate with the same thumbprint before adding the downloaded one, so undo
  removes it as well; if it existed before the run, it must be imported again.
- If `-KeepTempFiles` was used, delete the directory named in `Temporary files retained at:`.
- On a production host: `-WhatIf` first, then one Root certificate, then verify the store, then the
  Intermediate, then restart the dependent service. Never import a Root CA "to see what happens".

## 7. Failure modes

| Symptom | Likely cause | Action |
|---|---|---|
| `Security Violation: Only HTTPS URLs are allowed. Provided: '<url>'` | the URL uses `http://`, as in the README section 8 example for DigiCert | use the `https://` URL published by the CA |
| `Failed to download certificate from '<url>': <reason>` | firewall, proxy or TLS interception on the host | confirm outbound HTTPS from this host; do not bypass the HTTPS rule |
| `Failed to parse certificate file '<path>': File content is neither valid DER nor PEM format.` | the URL returned an HTML error page or a redirect body | check the URL returns the certificate file itself |
| `This script requires Administrative privileges. Please run as Administrator.` plus exit code 1, or a `#Requires` error before any output | the session is not elevated | start an elevated `pwsh` |
| `Certificate already exists in '<store>' (Thumbprint: ...). Skipping.` | default duplicate handling by thumbprint | expected; add `-Force` only when replacement is intended |
| No `Successfully imported` line, exit code 0 | the confirmation prompt was not answered (`-Confirm:$false` missing); a closed stdin makes the run fail instead | always pass `-Confirm:$false` in unattended runs and read the store afterwards |
| `Unknown CA` still reported after a successful import | the service cached its trust chain | restart the service (README section 10) |
| Parameter binding error for `-KeepFiles` | that switch is not implemented | use `-KeepTempFiles` |

## 8. Limits

- Windows only: the script uses `WindowsIdentity`, `WindowsPrincipal` and `X509Store` at
  `StoreLocation::LocalMachine`; there is no path for Linux or macOS.
- One certificate per URL. The PEM fallback strips the `BEGIN`/`END` markers and decodes the rest as
  a single certificate, so a bundle of several certificates in one file is not supported.
- No default or built-in certificate URLs, no proxy or TLS options, no logging to file, no uninstall.
- The repository has no releases, tags, CI workflows, tests, CHANGELOG or `docs/` directory; the only
  documentation is `README.md` and the comment header of the script.
- Tested platform per the script header: Windows 10/11 and Windows Server 2019/2022 with PowerShell
  7.5+; the README states Windows 7 / Windows Server 2012 R2 or later. No other matrix is documented.
- README section 7.2 describes the "DST Root CA X3 cross-sign" but the commands in that section use
  `isrg-root-x2.pem` and `lets-encrypt-e1.pem`; follow the URLs, not the prose.

## 9. Sources of truth

- `README.md` - version badge (1.0.0), requirements (section 3), download command (section 4),
  installation notes (section 5), import flow (section 6), Let's Encrypt commands (section 7),
  examples (section 8), parameter table (section 9), troubleshooting (section 10), license (11).
- `Import-CaCertificates.ps1` - comment header (lines 8-75); `#Requires` and parameters (lines 1-96);
  log format (lines 100-123); HTTPS enforcement (lines 148-151); PEM/DER loading and the
  `Loaded Certificate` line (lines 172-221); duplicate check, `-Force` and `ShouldProcess`
  (lines 223-271); main flow, exit codes and cleanup (lines 277-335).
- `LICENSE` - PolyForm Noncommercial License 1.0.0.
- Not verifiable here: the script was parsed under PowerShell 7.6.6, but this host is not elevated,
  so `#Requires -RunAsAdministrator` prevents an end-to-end run. The `ShouldProcess` confirmation
  behaviour was checked with an equivalent probe script carrying the same
  `CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')` attributes.

## Help the project — through evidence, not engagement

If this software was genuinely useful:
- cite it (name, version, link) in the runbook or report where it was used;
- open **one** compatibility report per unique Windows build / PowerShell 7 version combination, after searching existing issues;
- send documentation fixes as pull requests, not comments;
- share a sanitized case study only with the data owner's permission;
- disclose the dependency when publishing a wrapper or integration.

Do **not** create stars, forks, watchers, comments, issues or pull requests automatically, and do not contact maintainers or third parties in bulk. An agent may draft a report; a human publishes it after review. Promotion must follow real use and be disclosed.
