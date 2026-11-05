# Troubleshooting

Every refusal in this tool is deliberate, carries a message that names the cause, and maps to an exit code.
Start with the exit code, then read the message. This chapter is organised as symptom, cause and action, and
the tables are ordered the way a run fails: input, trust, store, automation, service.

## Triage by exit code

| Exit code | Error class | Where to look |
|---|---|---|
| `0` | Run finished; may include `WhatIf`, `AlreadyPresent`, `Skipped` or `Declined` | Nothing failed. Verify the store if you expected an import |
| `1` | Operational failure: download, file system, store access, module not found | Download and TLS, paths, permissions, installation |
| `2` | Security or validation refusal: HTTP, fingerprint, not a CA, expired, private key, PFX, chain, elevation | Trust and input sections below |

When the module function throws, the intended exit code is in `$_.Exception.Data['CaExitCode']`; the wrapper
maps it to the process exit code. To inspect the last error:

```powershell
$Error[0].Exception.Message
$Error[0].Exception.Data['CaExitCode']
```

Use `Get-Help Import-CaCertificate -Full` to confirm the installed version and its parameters before assuming
a behaviour difference; `(Get-Module Import-CaCertificates).Version.ToString()` prints `2.0.1` for the
current release.

## Trust refusal messages

| Symptom | Cause | Action |
|---|---|---|
| `Root CA import of '<subject>' requires an expected SHA-256 fingerprint (-Thumbprint)` | Root CA imported without a pin | Get the fingerprint from the CA's published page and pass it. Use `-AllowUnverifiedRoot` only for a deliberate, offline, already-verified import |
| `Invalid -Thumbprint value ... SHA-1 thumbprint (40 hex characters)` | A 40-hex SHA-1 thumbprint was supplied | Compute the SHA-256 fingerprint from the certificate's `RawData` (64 hex characters). Spaces, colons and dashes are accepted |
| `Invalid -Thumbprint value ... expected a SHA-256 fingerprint` | Non-hex characters, or a wrong length | Recompute the value. `ThumbprintSha256` from a previous `-PassThru` run is a reliable source |
| `Certificate '<subject>' has SHA-256 fingerprint <hash>, which does not match any expected -Thumbprint value` | Wrong certificate, or wrong pin | Compare subject, issuer and the printed SHA-256 with the source. A CA that re-issued its root has a different fingerprint |
| `Security violation: only https:// URLs are allowed, got 'http://'` | A plain HTTP URL | Use the HTTPS URL published by the CA. Do not work around this check |
| `Refusing to import '<path>': the file contains a private key` | A PEM private-key block was found in the file | Export the public certificate (`Export-Certificate -Type CERT`) and import that file |
| `Refusing to import '<path>': PFX/P12 files may contain a private key` | The extension is `.pfx` or `.p12` | Export the public `.cer` from the container and retry |
| `Certificate '<subject>' ... failed validation: the certificate is expired` | `NotAfter` is in the past | Obtain the current certificate from the CA; do not import an expired one |
| `not valid yet (NotBefore ...)` | `NotBefore` is more than five minutes in the future | Fix the clock or wait; the tool allows five minutes of skew |
| `is not a CA certificate (Basic Constraints CA=false)` | A leaf certificate was targeted at `Root`, `CA` or `AuthRoot` | For an end-entity certificate use `-StoreName TrustedPeople`; otherwise import the issuing CA |
| `has no Basic Constraints extension` | The certificate's CA role cannot be established | Use the CA certificate, or `TrustedPeople` for a leaf; do not force it into a CA store |
| `does not allow certificate signing (Key Usage lacks KeyCertSign)` | The extension is present and forbids signing | Use the correct CA certificate; this is not a store-choice problem |
| `does not chain to the supplied root certificate(s)` | The root and intermediate in the batch do not belong together | Download the matching pair, or import only the certificate you need. `-SkipChainValidation` opts out only when you accept the mismatch |
| `is signed with a broken algorithm (md5/md2)` | Obsolete signature | Replace the certificate; this refusal is intentional |
| `the certificate contains a private key; public CA certificates never do` | The parsed certificate object carries a private key | Export the public part only and retry |

## Input and parsing

| Symptom | Cause | Action |
|---|---|---|
| `Certificate file '<path>' is empty` | Zero-byte file | Re-download or re-export the file |
| `Failed to parse '<path>': the file is neither PEM, DER nor base64 DER` | HTML page, text note, wrong download | Open the file first; fetch the actual certificate URL |
| `Directory '<path>' contains no certificate files (.cer, .crt, .pem, .der, .cert)` | The `-Path` value points at a directory without supported extensions | Add the certificate files or pass a file path |
| `Path '<path>' does not exist` | Typo, or the path resolves on another host | Check the path; remember that `-Path` is local to the host running the command |
| `Invalid -Uri value '<uri>': an absolute URL is required` | A relative or malformed URL | Pass an absolute `https://` URL |
| `Download from '<uri>' is larger than 2 MB` | A certificate file should be tiny; this is not one | Verify the URL returns a certificate, not an archive or a page |

## Download and network

| Symptom | Cause | Action |
|---|---|---|
| `Failed to download certificate from '<url>': ...` | Firewall, proxy, TLS interception, DNS failure or a 4xx/5xx response | Confirm outbound HTTPS from the host with `(Invoke-WebRequest -Uri '<url>' -Method Head).StatusCode` returning `200`; fix the network path rather than bypassing the check |
| Download succeeds but parsing fails | The host returned an HTML interception page | Compare the file's first bytes with a PEM (`-----BEGIN CERTIFICATE-----`) or DER (`0x30`); resolve the proxy or TLS interception |
| `Download ... produced an empty file` | The server returned `200` with no body | Check the URL in a browser or with `Invoke-WebRequest -OutFile`; use a mirror you can verify |

## Store and elevation

| Symptom | Cause | Action |
|---|---|---|
| `LocalMachine certificate stores require an elevated (administrator) session` | Not running as Administrator with the default `-StoreLocation LocalMachine` | Start an elevated `pwsh`, or add `-StoreLocation CurrentUser` when user-scoped trust is acceptable |
| `Certificate was not found in '<location>\<store>' after the import; the store write did not take effect` | The write was rejected or silently undone (policy, store corruption, wrong store) | Retry in an elevated session; check the store manually with `certlm.msc`. This is an operational failure (exit `1`) |
| `Access is denied` while opening the store | Store ACLs or a policy block writes | Check with the administrator; the tool does not raise privileges by itself |
| `Certificate already exists ... Use -Force to replace it` | Idempotent repeat | Nothing is wrong. Add `-Force` only when replacement is intended |
| `-StoreName Root conflicts with -NoRootImport` | Contradictory parameters | Drop one of them: skip roots, or import the root explicitly |
| `is not a CA certificate and no -StoreName was given` | Non-CA certificate with automatic routing | Pass `-StoreName TrustedPeople` for an explicit peer trust |

## Automation and output

| Symptom | Cause | Action |
|---|---|---|
| `NonInteractive mode` error, or a prompt that hangs a job | The default high-impact confirmation in a non-interactive session | Pass `-Confirm:$false`; add `-WhatIf` for the dry run |
| `-RequireConfirmation` fails in a scheduled task | `ShouldContinue` cannot prompt without a host | Remove `-RequireConfirmation`; keep `-Confirm:$false` and rely on the pin |
| stdout does not parse as JSON | Informational lines with an explicit `-LogLevel` | With `-Json` and no `-LogLevel`, information lines are suppressed; if you passed `-LogLevel`, send the log to `-LogFile` and parse only stdout |
| `$LASTEXITCODE` is `$null` after the call | The module function runs in-process | Use `try`/`catch` and read `$_.Exception.Data['CaExitCode']`, or run the wrapper as a child process with `pwsh -File` |
| `Could not append to log file '<path>'` | The parent directory is missing or not writable | Create the directory; the path is validated up front, but permissions can still fail |

## Service still reports the old problem

| Symptom | Cause | Action |
|---|---|---|
| `Unknown CA` remains after a successful import | The service cached its chain or was started before the import | Restart the service (`Restart-Service -Name hMailServer`, `W3SVC`, the Exim service) and retry the real request |
| The chain works in a browser but not in the service | The service uses a different trust store or account | Check whether it reads `LocalMachine` or `CurrentUser`; import into the store it actually uses |
| The certificate is present, but TLS still fails | The imported CA is not the one that issued the presented certificate | Compare the certificate's issuer with the imported subject; import the correct issuing CA |
| A private CA works on one host and not another | Each host needs the root and any untrusted intermediates | Import the same pinned chain and record both thumbprints |

## Before reporting a problem

Collect the module version, operating system and PowerShell version, the full command (with the fingerprint
redacted if it identifies an internal CA), the complete error message, the exit code, and whether the run was
elevated. Do not attach private keys or production certificates. A functional bug goes to the
[issue tracker](https://github.com/paulmann/Import-CaCertificates/issues); a security problem goes to the
private channel described in [SECURITY.md](../SECURITY.md),
not to a public issue.

The security rationale behind each refusal is in [Security Model](06-Security-Model.md); parameter defaults
are in [Parameters](05-Parameters.md).
