# Parameters

The module exposes one command, `Import-CaCertificate`. The CLI wrapper `Import-CaCertificates.ps1` accepts
the same parameters plus three compatibility members, and maps module exceptions to process exit codes. There
is no configuration file and no environment variable; behaviour is set only by parameters.

## Parameter sets

| Set | Mandatory parameter | Position | Notes |
|---|---|---|---|
| `ByUri` | `-Uri` | 0 | Default set; accepts pipeline input |
| `ByPath` | `-Path` | 0 | Accepts pipeline input; a value may be a file or a directory |
| `Legacy` | `-RootUrl` | 0 | CLI wrapper only; mapped to `-Uri` with a deprecation warning |

## Module parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Uri` | `string[]` | - | HTTPS URL(s) of certificate files (PEM, DER, base64 DER or a multi-certificate PEM bundle). Mandatory in `ByUri` |
| `-Path` | `string[]` | - | Local certificate file(s) or directories of `.cer`, `.crt`, `.pem`, `.der`, `.cert` files. Mandatory in `ByPath` |
| `-Thumbprint` | `string[]` | - | Expected SHA-256 fingerprint(s), 64 hex characters; spaces, colons and dashes are ignored. Every imported certificate must match one value |
| `-StoreLocation` | `string` | `LocalMachine` | `LocalMachine` (requires elevation) or `CurrentUser` |
| `-StoreName` | `string` | auto | `Root`, `CA`, `AuthRoot` or `TrustedPeople`. Without it a self-signed CA goes to `Root` and another CA to `CA` |
| `-NoRootImport` | switch | off | Skip Root CA certificates instead of importing them |
| `-AllowUnverifiedRoot` | switch | off | Permit a Root CA import without `-Thumbprint`; warned and reported as unverified |
| `-RequireConfirmation` | switch | off | Ask an interactive yes/no question per certificate, in addition to `ShouldProcess`; not usable non-interactively |
| `-Force` | switch | off | Replace an entry with the same SHA-256 fingerprint; never bypasses verification |
| `-PassThru` | switch | off | Return one result object per certificate |
| `-Json` | switch | off | Return a single JSON envelope with `Version`, `Timestamp`, `Summary`, `Results` |
| `-LogLevel` | `string` | `Info` | `None`, `Error`, `Warning`, `Info` or `Verbose` |
| `-LogFile` | `string` | - | Append log lines (UTF-8, no BOM) to this file; the parent directory must exist |
| `-KeepTempFiles` | switch | off | Keep downloaded files in the temporary directory |
| `-TempPath` | `string` | `$env:TEMP` | Parent for a unique `CaImport_<id>` subdirectory that is removed after the run |
| `-SkipChainValidation` | switch | off | Skip the signature-chain check between supplied roots and intermediates |
| `-WhatIf` / `-Confirm` | common | - | Standard `ShouldProcess`; `ConfirmImpact = High` |

## Wrapper-only parameters

| Parameter | Status | Description |
|---|---|---|
| `-RootUrl` | deprecated | HTTPS URL of a Root CA certificate; mapped to `-Uri`, warning printed, removal planned for 3.0.0 |
| `-IntermediateUrl` | deprecated | HTTPS URL of an Intermediate CA certificate; same mapping and warning |
| `-KeepFiles` | alias | Alias of `-KeepTempFiles`, kept for compatibility with the 1.x documentation |

## Aliases

Aliases exist so that pipeline and discovery scenarios work; they are not separate parameters.

| Parameter | Aliases |
|---|---|
| `-Uri` | `-CertificateUri`, `-Url` |
| `-Path` | `-LiteralPath`, `-FilePath` |
| `-Thumbprint` | `-ExpectedThumbprint`, `-Fingerprint`, `-Sha256` |
| `-KeepTempFiles` | `-KeepFiles` (wrapper) |

## Store routing

| Certificate | No `-StoreName` | Explicit `-StoreName` |
|---|---|---|
| Self-signed CA | `Root` | The requested store |
| Non-self-signed CA | `CA` | The requested store |
| Not a CA | Refused: "not a CA certificate and no -StoreName was given" | `TrustedPeople` only; `Root`, `CA` and `AuthRoot` refuse it |

`Root`, `CA` and `AuthRoot` accept only certificates with Basic Constraints `CA=true` and Key Usage
`keyCertSign`; a missing Key Usage extension produces a warning rather than a refusal. `TrustedPeople`
accepts non-CA certificates because it is explicit trust for a peer.

Two combinations are refused outright: `-StoreName Root` together with `-NoRootImport` (contradictory
instructions), and a Root CA import without `-Thumbprint` unless `-AllowUnverifiedRoot` is present. With an
explicit `-StoreName Root`, a non-self-signed certificate is imported with a warning instead of being
redirected.

## Validation and write order

For each certificate the tool performs these steps in this order; a failure stops the run at that step:

1. Parse the input as PEM (possibly multi-certificate), DER or base64 DER.
2. Refuse a file or certificate that contains private key material.
3. Check the validity period: `NotBefore <= now + 5 min` and `NotAfter >= now - 5 min`.
4. Require Basic Constraints `CA=true` for `Root`, `CA` and `AuthRoot`.
5. Require Key Usage `keyCertSign` when the extension is present; warn when it is absent.
6. Refuse MD2/MD5 signatures; warn on SHA-1.
7. Warn on RSA keys below 2048 bits and ECDSA keys below 256 bits.
8. Choose the target store (explicit `-StoreName`, otherwise automatic routing).
9. Compare the certificate SHA-256 with every `-Thumbprint` value; a mismatch is refused.
10. Enforce the Root CA fingerprint policy unless `-AllowUnverifiedRoot` is present.
11. Chain-check an intermediate against roots supplied in the same batch, unless `-SkipChainValidation`.
12. Ask for confirmation when `-RequireConfirmation` is set; `ShouldProcess` handles `-WhatIf` and `-Confirm`.
13. Write the certificate, then read the store back and confirm the SHA-256 fingerprint is present.

Step 13 is why `Imported` means more than "the add call returned": a certificate that cannot be read back is
an error. The same sequence is described from the threat side in [Security Model](06-Security-Model.md).

## Behaviour worth knowing

### Thumbprint normalisation

The value is upper-cased and stripped of spaces, colons, dashes and a leading `0x`. A 40-hex value is
recognised as a SHA-1 thumbprint and refused with a message that names SHA-1, because the identity check is
SHA-256. Any other malformed value is refused as invalid. Both refusals use exit code `2`.

### JSON and logging

With `-Json` and no explicit `-LogLevel`, the effective level is `Warning`, so the `[Info]` chatter does not
corrupt stdout; warnings and errors still reach their streams and the log file. Pass `-LogLevel Info`
explicitly if you want both the JSON document and the informational lines.

### Temporary files

Downloads go into a unique directory `CaImport_<12 hex>` under `-TempPath` (default `$env:TEMP`). It is
removed after the run. `-KeepTempFiles` keeps it and prints `Temporary files retained at: <path>`; delete that
directory yourself. Existing files in `-TempPath` are never deleted, because only the unique subdirectory is
touched.

### Chain validation

When a root and one or more intermediates are supplied in the same batch, the intermediates are validated
with a chain built from the supplied roots only (`CustomRootTrust`, revocation checking off, certificate
downloads disabled). `-SkipChainValidation` opts out, and is appropriate when you deliberately import only
part of a chain. Cross-signed roots have a different issuer, so they are treated as intermediates.

### Force is not a bypass

`-Force` only replaces a certificate with the same SHA-256 fingerprint. It does not uninstall, does not
replace by subject, and does not relax any check. A certificate that fails validation or fingerprint
matching is refused whether or not `-Force` is present.

## Examples

```powershell
# Dry run a URL with an explicit store
Import-CaCertificate -Uri 'https://ca.example.com/intermediate.pem' -Thumbprint '<sha256>' `
    -StoreName CA -WhatIf -Confirm:$false

# Return objects and log at Verbose
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' `
    -PassThru -LogFile 'C:\logs\ca.log' -LogLevel Verbose -Confirm:$false

# Explicit trust for one partner certificate
Import-CaCertificate -Path 'C:\certs\partner-leaf.pem' -Thumbprint '<sha256>' `
    -StoreName TrustedPeople -Confirm:$false

# Deliberate, offline, already-verified unverified-root import
Import-CaCertificate -Path 'D:\transfer\root.cer' -AllowUnverifiedRoot -Confirm:$false
```

Task scenarios that use these parameters are in [Usage](04-Usage.md); the refusals each validation step can
produce are listed in [Troubleshooting](07-Troubleshooting.md).
