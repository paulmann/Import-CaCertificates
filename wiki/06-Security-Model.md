# Security Model

Importing a CA certificate is a trust decision, and for `LocalMachine\Root` it is a machine-wide one. This
chapter describes what the tool protects, how the controls work, and what it deliberately does not do. The
authoritative source is
[docs/SECURITY-MODEL.md](../docs/SECURITY-MODEL.md);
this page is the manual's operational summary.

## Assets and impact of a wrong import

| Store | Impact if the wrong certificate is imported |
|---|---|
| `LocalMachine\Root` | Machine-wide trust anchor: every account and service on the host accepts certificates issued under this CA. A malicious root is a system-wide trust compromise |
| `LocalMachine\CA` | Intermediates are constrained by their issuing root, but a malicious intermediate enables impersonation if its root is trusted |
| `CurrentUser\Root` / `CurrentUser\CA` | Trust limited to one user profile, still relevant for services and scripts running as that user |
| `TrustedPeople` | Explicit trust for specific end-entity certificates; lower blast radius |

The tool never touches private keys, certificate requests, revocation lists or services. Its only write is
adding a certificate to one store, and with `-Force` removing an entry with the same SHA-256 fingerprint
before adding the replacement.

## Threats considered

| Threat | Mitigation |
|---|---|
| Certificate swapped in transit (HTTP, compromised mirror, DNS hijack) | HTTPS is enforced before any request; the certificate must match the expected SHA-256 fingerprint |
| Wrong certificate from the right URL (CA re-issue, page redesign) | The fingerprint must match; mismatches are refused before any store write |
| Missing or extra certificates in a bundle | Every imported certificate must be pinned; the bundle is parsed certificate by certificate |
| Private key or PFX imported by accident | Files with a PEM private-key block and `.pfx`/`.p12` extensions are refused |
| Expired or not-yet-valid CA | `NotBefore`/`NotAfter` are checked with a five-minute clock-skew tolerance |
| End-entity certificate imported as a CA | Basic Constraints `CA=true` and Key Usage `keyCertSign` are required for `Root`, `CA` and `AuthRoot` |
| Broken signature algorithm | MD2/MD5-signed certificates are refused; SHA-1 is reported as a warning |
| Mismatched root and intermediate | When both are in the same batch, a chain is built with `CustomRootTrust` against the supplied roots and must validate |
| Silent replacement of a different certificate | Deduplication and replacement use the SHA-256 fingerprint; a certificate with a different fingerprint is never removed implicitly |
| Unattended high-impact write | `ConfirmImpact = High` prompts interactively; automation must pass `-Confirm:$false` explicitly |

## What is verified, in order

For each certificate: parse (PEM, DER, base64 DER); refuse private key material; check the validity period;
require CA role for CA stores; require `keyCertSign` when Key Usage is present; refuse MD2/MD5 and warn on
SHA-1; warn on weak keys; choose the store; match the SHA-256 fingerprint; enforce the Root CA policy;
chain-check intermediates against supplied roots; ask for confirmation; write and read back. The step-by-step
list with parameter effects is in [Parameters](05-Parameters.md#validation-and-write-order).

Two details make the order meaningful. First, the fingerprint check happens before `ShouldProcess`, so
`-WhatIf` still validates the pin; a dry run that prints `WhatIf` is evidence that the certificate matched.
Second, the write is followed by a read-back of the store, so `Imported` means the certificate was found in
the store after the add, not merely that the API call returned.

## Limits and non-goals

These are documented limits, not defects:

- **Self-signed detection is a heuristic.** Subject and issuer distinguished names are compared. A
  cross-signed root is treated as an intermediate (correct store for it); a self-issued but not self-signed
  CA is treated as a root, so verify it manually if that distinction matters.
- **No revocation checking.** OCSP and CRL are not queried. Offline imports are a first-class scenario and a
  root's revocation status at import time is not meaningful.
- **No Certificate Transparency checks.** CT is a web-PKI control and is not applied here.
- **No protection against a malicious CA.** A pinned fingerprint proves the file is the certificate you
  intended to trust, not that the CA is trustworthy.
- **No file hash verification.** `-Thumbprint` is the SHA-256 of the certificate's DER encoding, not
  `Get-FileHash` of the PEM file; the two differ because PEM adds base64 text. Compute the certificate hash
  from `RawData` as shown in [Quick Start](03-Quick-Start.md).
- **`-Force` is not a bypass.** It replaces a certificate with the same SHA-256 fingerprint and never
  imports a certificate that failed validation or pinning.
- **Privileges are not changed by the tool.** It requires the access the store needs and never raises or
  lowers privileges; `LocalMachine` without elevation is refused.
- **`-AllowUnverifiedRoot` removes the main control.** It is intended only for controlled, offline,
  already-verified imports. Prefer pinning.

## Operational guidance

1. Obtain the fingerprint from the CA's own published page or from your PKI documentation, never from the
   same URL you are downloading from.
2. Run `-WhatIf` first and read the printed subject, issuer, validity period and SHA-256.
3. Import on a test host, restart the dependent service and confirm the chain works.
4. On production, import one certificate at a time, verify the store, then restart the service.
5. Record the version, URL or file, SHA-256 and date of every trust-store change in the runbook.
6. Keep `-LogFile` output for audit when automation makes the change.

For hMailServer, Exim and IIS sequences see
[docs/EXAMPLES.md](../docs/EXAMPLES.md). The
deployment pattern for a fleet is one pinned certificate per run, `-Json` for the machine-readable record,
and exit code `2` treated as an alert rather than a retryable error.

## Supported versions and disclosure

| Version | Supported |
|---|---|
| 2.x | Yes, current release line |
| 1.x | No; replaced by 2.0.0 because Root CA imports could be made without fingerprint verification |

Do not open a public issue for a security problem. Report it privately as described in
[SECURITY.md](../SECURITY.md), including the
affected version, operating system, PowerShell version, impact, minimal reproduction steps and whether you
want credit. Acknowledgement is expected within 7 days and a fix within 30 days before public disclosure.
In scope are fingerprint bypasses, non-HTTPS import paths, private-key import, writes to an unintended store,
command injection or path traversal, temporary-file handling, elevation bypass and logging of secret
material. Out of scope are CA policy decisions, compromise of a CA's own infrastructure, Windows store
internals, missing OCSP/CRL/CT checks and third-party platform issues.

## Hardening recommendations

1. Pin fingerprints obtained through an independent, trusted channel.
2. Run `-WhatIf` and review the printed identity and validity before the real run.
3. Prefer `-Path` with a locally verified file over `-Uri` on high-value hosts.
4. Keep `-LogFile` output for audit and monitor exit codes `1` and `2`.
5. Never use `-AllowUnverifiedRoot` in automation.
6. Keep the module at the latest 2.0.x release so that validation fixes apply.
