# Migration from 1.x

Version 2.0.0 is a security-focused rewrite, and the command's behaviour changed on purpose. Version 2.0.1
adds no code or behaviour changes; it relicenses the project under MIT. Read this chapter before replacing a
working 1.x script, especially in an unattended deployment.

## What changed at a glance

| 1.x | 2.0.x |
|---|---|
| Single PowerShell script | Module `Import-CaCertificates` with the command `Import-CaCertificate`, plus a thin CLI wrapper |
| `-RootUrl` and `-IntermediateUrl` | `-Uri` takes a list. The deprecated names still work in the wrapper, print a warning, and are planned for removal in 3.0.0 |
| No fingerprint check | `-Thumbprint` (SHA-256, 64 hex) is required for every imported certificate; a Root CA is refused without it unless `-AllowUnverifiedRoot` is passed |
| `-KeepFiles` (documented) / `-KeepTempFiles` (implemented) | `-KeepTempFiles`; `-KeepFiles` is an alias in the wrapper |
| `-TempPath` was used directly | A unique `CaImport_<id>` subdirectory is created under `-TempPath` and only that subdirectory is removed |
| One certificate per URL | Multi-certificate PEM bundles, local files (`-Path`), directories, DER and base64 DER |
| Root vs intermediate chosen by parameter | Chosen by certificate type, or forced with `-StoreName` (`Root`, `CA`, `AuthRoot`, `TrustedPeople`) |
| Duplicate check by SHA-1 thumbprint | Deduplication and replacement by SHA-256 fingerprint; SHA-1 is still reported for `certmgr.msc`/`certutil` |
| Console log only | `-PassThru` objects, `-Json` envelope, `-LogFile`, `-LogLevel`, and exit codes `0`, `1`, `2` |
| "Windows 7 / Server 2012 R2" claim | Windows 10 1607+ / Windows 11 and Windows Server 2012 R2+ with PowerShell 7.4+; Windows 7 is not supported |

## Breaking changes

1. **Root CA imports require a fingerprint.** The 1.x flow of importing whatever a URL returned is gone. Get
   the SHA-256 value from the CA's published page, or from your PKI documentation, before the upgrade.
2. **The parameters `-RootUrl` and `-IntermediateUrl` are deprecated.** They are mapped to `-Uri` with a
   warning and will be removed in 3.0.0. Replace them in scripts now.
3. **The supported platform matrix is narrower and truthful.** Windows 10 1607+, Windows 11 and Windows
   Server 2012 R2+ with PowerShell 7.4+. Windows 7, which 1.x claimed, is not supported.
4. **`-TempPath` semantics changed.** The tool now creates a unique subdirectory and deletes only that
   subdirectory; existing files under `-TempPath` are never deleted.
5. **Requirements are enforced.** `#Requires -Version 7.4` in the module and the wrapper; Windows PowerShell
   5.1 is out.

## What 2.0.x adds that 1.x did not have

- Certificate validation: X.509 parsing, validity period with five-minute skew, Basic Constraints `CA=true`,
  Key Usage `keyCertSign`, MD2/MD5 refusal, SHA-1 warning, weak-key warnings.
- Chain validation of intermediates against roots supplied in the same batch (`-SkipChainValidation` opts
  out).
- Refusal of plain HTTP, PFX/P12 and any file containing a private key.
- Idempotent store handling with the statuses `Imported`, `Replaced`, `AlreadyPresent`, `Skipped`, `WhatIf`,
  `Declined`.
- Structured reporting: `-PassThru` result objects, `-Json` envelope, `-LogFile`, `-LogLevel`, exit codes.
- `-RequireConfirmation` for an explicit per-certificate interactive yes/no prompt.

The full release narrative is in
[CHANGELOG.md](../CHANGELOG.md).

## Upgrade checklist

1. **Inventory the old calls.** Search your scripts, scheduled tasks and runbooks for `-RootUrl`,
   `-IntermediateUrl` and `-KeepFiles`. Every hit is a migration item.
2. **Collect fingerprints.** For every CA the old script imported, obtain the SHA-256 fingerprint from the
   CA's published page or from PKI documentation. Do not compute it from the same URL the script downloads.
3. **Install 2.0.1 side by side.** Extract the release archive to a new directory and verify it with
   `SHA256SUMS.txt` as described in [Install](02-Install.md). Keep the old script until the new runs pass.
4. **Rewrite one call.** Replace `-RootUrl`/`-IntermediateUrl` with `-Uri`, add `-Thumbprint`, and add
   `-Confirm:$false` because automation cannot answer the high-impact prompt.
5. **Dry run on a test host.** Use `-WhatIf -Confirm:$false -PassThru` and read the subject, issuer,
   validity and SHA-256 that are printed. A `WhatIf` status means the pin matched.
6. **Import and verify.** Run without `-WhatIf`, verify the store, restart the dependent service and test a
   real connection.
7. **Cut over automation.** Switch the scheduled task or deployment script to the wrapper so that the process
   gets exit codes `0`, `1`, `2`; treat `2` as an alert, not a retry.
8. **Record the change.** Note the version, URL or file, SHA-256 and date in the runbook. Keep the `-LogFile`
   output as evidence.
9. **Remove the old copy** once every caller has moved and the store contents are confirmed.

A before-and-after pair for the most common call:

```powershell
# 1.x
.\Import-CaCertificates.ps1 -RootUrl 'https://ca.example.com/root.cer' -KeepFiles

# 2.0.x
.\Import-CaCertificates.ps1 -Uri 'https://ca.example.com/root.cer' `
    -Thumbprint '<sha256-root>' -Confirm:$false -PassThru
```

## License change

The project moved to the **MIT License** in 2.0.1. Releases 2.0.0 and earlier were published under the
PolyForm Noncommercial License 1.0.0. No code, behaviour or API changed in 2.0.1. If the earlier license was
the reason you could not adopt the tool, 2.0.1 removes that obstacle; see
[LICENSE](https://github.com/paulmann/Import-CaCertificates/blob/main/LICENSE).

## Rollback

If the new version cannot be adopted immediately, the old script still exists in your deployment, but it has
the security property that 2.0.0 removed: a Root CA can be imported without a fingerprint. Treat that as a
temporary state, pin the fingerprint in the old script's input (verify the downloaded file yourself before
importing it), and plan the move. Do not leave an unpinned root import in automation.

For a certificate imported by 2.0.x, rollback means removing the SHA-1 thumbprint reported in the result
object:

```powershell
Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<SHA-1-thumbprint>
```

Then restart the dependent service. If a `-Force` run replaced an earlier copy, re-import the original from a
trusted source.

## After the upgrade

- [Parameters](05-Parameters.md) for every option and default.
- [Security Model](06-Security-Model.md) for the controls the upgrade buys.
- [Troubleshooting](07-Troubleshooting.md) for the new refusal messages.
- [FAQ](10-FAQ.md) for the questions that come up during a migration.
