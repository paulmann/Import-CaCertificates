# Why Import-CaCertificates

TLS verification fails on a Windows host for one practical reason: the machine trust store does not contain
the CA that issued the certificate the service presents. The usual fix is to download "the CA certificate"
from a search result, a forum post or the same server that is failing, and import it. That fix quietly
replaces a cryptographic identity check with trust in a download.

Import-CaCertificates exists to make the trust decision explicit. You supply the SHA-256 fingerprint of the
certificate you intend to trust, obtained from the CA's own published page or from your PKI documentation,
and the tool refuses to write anything that does not match it.

## The problem with "download and import"

A certificate served over an untrusted connection is just a file. The realistic failure modes are:

| Failure mode | What happens without pinning |
|---|---|
| DNS hijack or compromised mirror | The URL returns an attacker's CA certificate; it is imported and every certificate under it is trusted machine-wide |
| CA re-issues or rotates its root | The URL returns a different certificate than the one your runbook approved; nothing notices |
| Page redesign | The URL returns an HTML page or a bundle with extra certificates; the tool imports what it can parse |
| Wrong file | Someone copies a certificate from the wrong project; the subject looks plausible and nobody checks |
| Bundle with unexpected members | A multi-certificate PEM contains one extra certificate; it gets imported alongside the intended ones |

A pinned SHA-256 fingerprint closes all five: the certificate's DER encoding is hashed and compared with the
expected value before any store write. It is the difference between "trust this file because of where it
came from" and "trust this file because it is byte-identical to the certificate I decided to trust".

## What version 2.0 changed

Version 1.x was a single script that downloaded a Root CA and optionally an Intermediate CA from HTTPS URLs
and imported them. It had no fingerprint model, accepted plain HTTP examples, and its README claimed a
Windows 7 support it did not have. Version 2.0.0 is a security-focused rewrite; 2.0.1 relicensed the project
under MIT. The changes that matter for trust are:

- A Root CA import requires `-Thumbprint` unless the explicit `-AllowUnverifiedRoot` override is passed.
- Every imported certificate is pinned, including intermediates and bundle members.
- Plain HTTP URLs, PFX/P12 containers and files containing private keys are refused before any write.
- Certificates are validated (validity period, CA role, Key Usage, signature algorithm, key strength) and a
  root/intermediate pair supplied in the same batch is chain-checked.
- Deduplication and replacement use the SHA-256 fingerprint; the SHA-1 thumbprint is reported only for
  `certmgr.msc` and `certutil` compatibility.
- Results are structured (`-PassThru`, `-Json`), loggable (`-LogFile`) and mapped to exit codes `0`, `1`, `2`.

The full mapping is in [Migration from 1.x](08-Migration-from-1.x.md), and the release history is in
[CHANGELOG.md](../CHANGELOG.md).

## What pinning does and does not buy

A pinned fingerprint proves that the file is the certificate you intended to trust. It does not prove that
the CA is trustworthy, that the CA is still in business, or that the certificate is not revoked. The tool
documents those limits instead of implying a guarantee:

- **Self-signed detection is a heuristic.** Subject and issuer distinguished names are compared. A
  cross-signed root is treated as an intermediate, which is the correct store for it; a self-issued but not
  self-signed CA is treated as a root, so verify it manually if that matters.
- **No revocation checking.** OCSP and CRL are not queried, because offline imports are a first-class
  scenario and a root's revocation status at import time is not meaningful.
- **No Certificate Transparency checks.** CT is a web-PKI control and is not applied here.
- **No protection against a malicious CA.** Only against the wrong file.
- **`-Force` is not a bypass.** It replaces a certificate with the same SHA-256 fingerprint; it never skips
  validation or fingerprint matching.

The reasoning is expanded in [Security Model](06-Security-Model.md) and in
[docs/SECURITY-MODEL.md](../docs/SECURITY-MODEL.md).

## What the tool is not

It is not a certificate manager. It does not request, renew, back up, list or remove certificates; it does
not manage services, configuration files or private keys; it does not touch OCSP, CRL or CT; it does not
run on Linux or macOS (it uses `WindowsIdentity`, `X509Store` and Windows stores); and it does not protect
you from a CA you deliberately chose to trust.

Use it when the task is exactly "make this host trust this CA chain, verifiably". For a full PKI lifecycle
use a PKI product. For a one-off drag-and-drop, `certmgr.msc` still works, but it will not tell you what you
imported, will not refuse a private key, and will not record a fingerprint.

## When to use it

| Situation | Good fit |
|---|---|
| hMailServer, Exim or IIS reports `Unknown CA` for an external TLS certificate | Yes: import the issuing CA, restart the service |
| An internal corporate PKI root and intermediates must be trusted on servers | Yes: import the pinned chain, keep the log |
| Air-gapped host needs a CA already verified on a connected machine | Yes: use `-Path` with the fingerprint |
| A fleet needs an auditable, idempotent CA import run | Yes: `-Json` or `-LogFile` plus exit codes `0`, `1`, `2` |
| You need to renew, revoke or inventory certificates | No: use a PKI or certificate lifecycle tool |
| You need to trust a private key or a PFX bundle | No: the tool refuses private key material by design |

Continue with [Install](02-Install.md) for the release archive, or [Quick Start](03-Quick-Start.md) if the
tool is already installed and you want the first verified run.
