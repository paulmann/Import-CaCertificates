# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 2.x | Yes, current release line |
| 1.x | No — replaced by 2.0.0 because Root CA imports could be made without fingerprint verification |

## Reporting a vulnerability

Do **not** open a public issue for a security problem.

Send a report to **m@deynekin.com** with the subject `Import-CaCertificates security`
and include:

- affected version (from the release tag or `Get-Module Import-CaCertificates`),
- operating system and PowerShell version,
- a description of the issue and the impact (for example: "a Root CA can be imported
  from a plain HTTP URL", "a fingerprint check can be bypassed with ..."),
- minimal reproduction steps, and, if possible, a proof-of-concept certificate or
  script that contains no real secrets,
- whether you are willing to be credited in the release notes.

You will receive an acknowledgement within 7 days. Please allow up to 30 days for a
fix before publishing details; coordinated disclosure is expected.

## In scope

- Bypass of the SHA-256 fingerprint verification or the `-AllowUnverifiedRoot` policy.
- Any path that imports a certificate from a non-HTTPS URL.
- Importing private key material (PEM with a private key, PFX/P12).
- Writing to an unintended store or certificate, or removing a certificate that does
  not have the same SHA-256 fingerprint.
- Command injection, path traversal or unsafe handling of temporary files.
- Elevation or privilege issues (for example, a way to write to `LocalMachine` without
  administrator rights).
- Logging or reporting of secret material.

## Out of scope

- A CA issuing a certificate you do not want to trust; that is a policy decision.
- Compromise of a CA's own publishing infrastructure.
- Windows certificate store internals, Autoptimization of the root program, or Windows
  behaviour that is not controlled by this project.
- Missing OCSP/CRL/CT checks: they are documented non-goals (see
  [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md)).
- Issues in third-party PowerShell modules or the GitHub platform.

## Hardening recommendations

1. Pin fingerprints obtained from an independent, trusted channel.
2. Use `-WhatIf` and review the printed subject, issuer, validity and SHA-256.
3. Prefer `-Path` with a locally verified file over `-Uri` on high-value hosts.
4. Keep `-LogFile` output for audit and monitor failures.
5. Never use `-AllowUnverifiedRoot` in automation.
