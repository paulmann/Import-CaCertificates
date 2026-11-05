# Security model

This document describes what Import-CaCertificates protects, how it does so, and what
it deliberately does not do. Read it before importing a Root CA on a production host.

## 1. Assets and impact

| Asset | Impact of a wrong import |
|---|---|
| `LocalMachine\Root` | Machine-wide trust anchor: every account and service on the host will accept certificates issued under this CA. A malicious root is a system-wide trust compromise. |
| `LocalMachine\CA` | Intermediates are constrained by their issuing root, but a malicious intermediate still enables impersonation if its root is trusted. |
| `CurrentUser\Root` / `CurrentUser\CA` | Trust limited to one user profile, but still relevant for services and scripts running as that user. |
| `TrustedPeople` | Explicit trust for specific end-entity certificates; lower blast radius. |

The utility never touches private keys, certificate requests, revocation lists or
services. Its only write operations are adding (and with `-Force`, removing) a
certificate in one of the stores above.

## 2. Threats considered

| Threat | Mitigation |
|---|---|
| Certificate swapped in transit (HTTP, compromised mirror, DNS hijack) | HTTPS is enforced; the downloaded certificate must match the expected SHA-256 fingerprint. |
| Wrong certificate from the right URL (CA re-issue, page redesign) | The fingerprint must match; mismatches are refused before any store write. |
| Missing or extra certificates in a PEM bundle | Every imported certificate must be pinned; the bundle is parsed certificate by certificate. |
| Private key or PFX accidentally imported | Files with `BEGIN ... PRIVATE KEY` blocks and `.pfx`/`.p12` extensions are refused. |
| Expired or not-yet-valid CA | `NotBefore`/`NotAfter` are checked (5-minute clock-skew tolerance). |
| End-entity certificate imported as a CA | Basic Constraints `CA=true` and Key Usage `keyCertSign` are required for Root/CA/AuthRoot stores. |
| Broken signature algorithm | MD2/MD5-signed certificates are refused; SHA-1 is reported as a warning. |
| Mismatched root and intermediate | When both are in the same batch, a chain is built with `CustomRootTrust` against the supplied root(s) and must validate. |
| Silent replacement of a different certificate | Deduplication and replacement use the SHA-256 fingerprint; a certificate with a different fingerprint is never removed implicitly. |
| Unattended high-impact write | `ConfirmImpact = High` prompts interactively; automation must pass `-Confirm:$false` explicitly. |

## 3. What is verified, in order

For each certificate:

1. Parse — PEM (possibly multi-certificate), DER, or base64 DER; anything else is an
   error.
2. No private key material — file contents and certificate object.
3. Validity period — `NotBefore <= now + 5 min`, `NotAfter >= now - 5 min`.
4. CA role — Basic Constraints `CA=true` for `Root`, `CA`, `AuthRoot`.
5. Signing capability — Key Usage `keyCertSign` when the extension is present; a
   missing Key Usage extension only produces a warning.
6. Signature algorithm — MD2/MD5 refused, SHA-1 warned.
7. Key strength — RSA below 2048 bits and ECDSA below 256 bits are warned.
8. Target store — explicit `-StoreName`, otherwise self-signed CA to `Root` and
   non-self-signed CA to `CA`.
9. Fingerprint — the certificate SHA-256 must be one of the `-Thumbprint` values.
10. Root policy — a `Root` import with no `-Thumbprint` is refused unless
    `-AllowUnverifiedRoot`.
11. Chain — intermediates are chain-checked against roots from the same batch unless
    `-SkipChainValidation` is set.
12. Confirmation — `ShouldProcess` (and optionally `ShouldContinue` with
    `-RequireConfirmation`).
13. Store write — add or replace, then read the store back and confirm the SHA-256
    fingerprint is present.

## 4. Limits and non-goals

- **Self-signed detection is a heuristic**: subject and issuer distinguished names are
  compared. A cross-signed root is treated as an intermediate (it has a different
  issuer), which is the correct place for it. A CA certificate that is self-issued but
  not self-signed is treated as a root; verify it manually if that matters.
- **No revocation checking**: OCSP/CRL checks are not performed. Offline imports are a
  first-class scenario, and a root's revocation status is not meaningful at import
  time.
- **No certificate transparency checks**: CT is a web-PKI control; it is not applied
  here.
- **No protection against a malicious CA**: a pinned fingerprint proves that the file
  is the certificate you intended to trust, not that the CA is trustworthy.
- **No file hash verification**: `-Thumbprint` is the SHA-256 of the certificate's DER
  encoding, not `Get-FileHash` of the PEM file (they differ; PEM adds base64 text).
- **`-Force` is not a bypass**: it replaces a certificate with the same SHA-256
  fingerprint. It never imports a certificate that failed validation or fingerprint
  matching.
- **Store access is not restricted beyond the requested store**: the process needs
  write access to the store; the tool does not raise or lower privileges by itself.
- **`-AllowUnverifiedRoot` removes the main control** and is intended only for
  controlled, offline, already-verified imports. Prefer pinning.

## 5. Operational guidance

1. Obtain the fingerprint from the CA's own published page or from your PKI
   documentation — never from the same URL you are downloading from.
2. Run `-WhatIf` first and read the subject, issuer, validity period and SHA-256 that
   are printed.
3. Import on a test host, restart the dependent service and confirm the chain works.
4. On production, import one certificate at a time, verify the store
   (`Get-ChildItem Cert:\LocalMachine\Root`), then restart the service.
5. Record the version, URL/file, SHA-256 and date of every trust-store change in your
   runbook.
6. To undo an import, remove the SHA-1 thumbprint reported in the result object:

   ```powershell
   Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
   ```

7. Keep `-LogFile` output for audit when changes are made by automation.
