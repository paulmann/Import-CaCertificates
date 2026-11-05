# Install

Import-CaCertificates is a PowerShell module plus a CLI wrapper; there is no installer, no MSI and no
PSGallery package as of 2.0.1. Installation is "put the files somewhere and import the module", and the
release archive is the supported channel because it ships with checksums.

## Requirements

| Requirement | Detail |
|---|---|
| Operating system | Windows 10 (1607 or later), Windows 11, Windows Server 2012 R2 or later |
| PowerShell | 7.4 or later (`pwsh`); Windows PowerShell 5.1 cannot load the module |
| Disk | A directory for the extracted archive, for example `C:\Tools\Import-CaCertificates` |
| Permissions to install | None beyond writing that directory; elevation is only needed later for `LocalMachine` store writes |
| Network | Needed only for `-Uri` imports and for downloading the release |

Windows 7 and Windows 8.1 are not supported: PowerShell 7 does not install there. Version 1.x claimed
Windows Server 2012 R2 support and Windows 7 support it did not have; 2.0.x states the supported matrix
explicitly.

## From a release (recommended)

Download `Import-CaCertificates-<version>.zip` and `SHA256SUMS.txt` from the
[Releases page](https://github.com/paulmann/Import-CaCertificates/releases/latest). Verify the archive before
extracting it; the checksum file lists `<sha256>  <filename>` lines.

```powershell
$zip = '.\Import-CaCertificates-2.0.1.zip'
$expected = (Select-String -Path .\SHA256SUMS.txt -Pattern '\.zip$').Line.Split(' ')[0]
(Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash -eq $expected
```

Expected output: `True`. If it prints `False`, stop: the archive is corrupted or not the published one.

Extract it to a tools directory:

```powershell
Expand-Archive -LiteralPath $zip -DestinationPath C:\Tools\Import-CaCertificates
Get-ChildItem C:\Tools\Import-CaCertificates
```

The archive contains the CLI wrapper (`Import-CaCertificates.ps1`), the module under
`src/Import-CaCertificates/`, the documentation (`README.md` and translations, `CHANGELOG.md`,
`SECURITY.md`, `CONTRIBUTING.md`, `docs/`) and `LICENSE`. The wrapper locates the module relative to its own
location, so the extracted directory can be moved or copied as a whole; do not separate the wrapper from
`src/`.

## From source

```powershell
git clone https://github.com/paulmann/Import-CaCertificates.git
Set-Location .\Import-CaCertificates
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Command Import-CaCertificate
```

From the repository root the wrapper can also be used directly:

```powershell
.\Import-CaCertificates.ps1 -Path .\root.pem -Thumbprint '<sha256>' -WhatIf -Confirm:$false
```

## Verify the installation

```powershell
Import-Module C:\Tools\Import-CaCertificates\src\Import-CaCertificates\Import-CaCertificates.psd1
(Get-Module Import-CaCertificates).Version.ToString()
Get-Command Import-CaCertificate | Select-Object -ExpandProperty Parameters
Get-Help Import-CaCertificate -Full
```

Expected: `2.0.1`, a parameter list containing `Uri`, `Path`, `Thumbprint`, `StoreLocation`, `StoreName`,
`NoRootImport`, `AllowUnverifiedRoot`, `RequireConfirmation`, `Force`, `PassThru`, `Json`, `LogLevel`,
`LogFile`, `KeepTempFiles`, `TempPath`, `SkipChainValidation`, `WhatIf` and `Confirm`, and the full
comment-based help.

## Module command or CLI wrapper

| Surface | Use it when | Behaviour on failure |
|---|---|---|
| Module function `Import-CaCertificate` | You are inside a PowerShell script or session and want objects, `try`/`catch` and the JSON envelope | Throws an exception; the intended process exit code is in `$_.Exception.Data['CaExitCode']` |
| Wrapper `Import-CaCertificates.ps1` | You need a process exit code for a scheduler, CI or another program | Catches the exception, prints the message and exits with the mapped code (`0`, `1` or `2`) |

The wrapper accepts the same parameters plus three compatibility members: `-RootUrl` and `-IntermediateUrl`
(deprecated, mapped to `-Uri` with a warning) and `-KeepFiles` (an alias of `-KeepTempFiles`). It imports the
module from `src/Import-CaCertificates/` relative to the wrapper's own path; if that path is absent it falls
back to an installed copy of the module, and if neither exists it exits `1` with a "module not found"
message.

## Update

Extract the new release archive into a new directory, verify its checksum the same way, and point your
scripts at the new path. There is no in-place updater. The module manifest, the `VERSION` file, the README
badge and the CHANGELOG move together; `Get-Module Import-CaCertificates` reports the loaded version, so
restart long-running sessions after an update.

## Remove

Remove the extracted directory, and remove the certificates you imported if they are no longer wanted. The
tool provides no uninstall command and does not track what it imported; every result object it produced
reports `ThumbprintSha1` for `certmgr.msc`/`certutil` and `ThumbprintSha256` for the identity check.

```powershell
# Undo one imported certificate (elevated for LocalMachine)
Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<SHA-1-thumbprint>
```

## Offline installation

Download the archive and `SHA256SUMS.txt` on a connected machine, copy both to the target host, verify the
hash there with the same command, then extract. The tool itself never contacts anything except the `-Uri`
values you pass, so an offline host needs no network access at run time when you use `-Path`. See
[Offline / air-gapped host](04-Usage.md#offline--air-gapped-host).

## Next steps

- First verified import: [Quick Start](03-Quick-Start.md)
- Every parameter and default: [Parameters](05-Parameters.md)
- The trust model before touching a production store: [Security Model](06-Security-Model.md)
