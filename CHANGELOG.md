# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- GitHub Wiki manual, authored in `wiki/` and published with `ghagent wiki publish`:
  Home, Why, Install, Quick Start, Usage, Parameters, Security Model, Troubleshooting,
  Migration from 1.x, Development, FAQ and For Agents.
- Community and metadata files: `CODE_OF_CONDUCT.md`, `SUPPORT.md`, `.editorconfig`,
  `CITATION.cff`, `.github/PULL_REQUEST_TEMPLATE.md`, three issue forms,
  `.github/CODEOWNERS` and `.github/dependabot.yml`.
- `assets/social-preview.png` (1280x640) and `assets/social-preview.svg`, used as the
  repository social preview and as the README banner.
- `docs/AGENT-GUIDE.md`: detailed agent operations (parameter table, failure modes,
  step-by-step runs) moved out of `AGENTS.md` so that `AGENTS.md` stays a map.

### Changed

- All six READMEs now open with a summary paragraph, carry a `Contents` heading, a
  navigation row and a documentation table linking the wiki, the docs site, the release
  page and the repository documentation files.
- `AGENTS.md` reduced to a map under 120 lines and linking to `docs/AGENT-GUIDE.md` for
  the details.
- Contact details in the READMEs and in `SECURITY.md` point to the GitHub profile and to
  GitHub private vulnerability reporting instead of a personal e-mail address.
- `CHANGELOG.md`: the `[Unreleased]` comparison link was added and the `2.0.0` sections
  were put in the Keep a Changelog canonical order.

### Fixed

- The unit-test fixture for the private-key refusal assembles its PEM marker at run time,
  so secret scanners no longer report `tests/Import-CaCertificates.Unit.Tests.ps1:130` as
  a private-key disclosure. Test behaviour is unchanged: 38 tests, 36 passed and 2
  skipped locally.

## [2.0.1] - 2026-11-06

### Changed

- Relicensed the project under the **MIT License** (see `LICENSE`). Release 2.0.0 and
  earlier were published under the PolyForm Noncommercial License 1.0.0. No code,
  behavior or API changes.

## [2.0.0] - 2026-11-05

### Added

- Module `Import-CaCertificates` with the public command `Import-CaCertificate`
  (`src/Import-CaCertificates/Import-CaCertificates.psd1` + `.psm1`) and a thin CLI
  wrapper (`Import-CaCertificates.ps1`).
- Mandatory SHA-256 fingerprint verification (`-Thumbprint`) for every imported
  certificate; Root CA imports additionally refuse to run without a fingerprint unless
  `-AllowUnverifiedRoot` is passed.
- Support for local files (`-Path`), directories of certificate files, multi-certificate
  PEM bundles, DER and base64 DER in addition to HTTPS URLs (`-Uri`).
- Certificate validation: X.509 parsing, validity period, Basic Constraints `CA=true`,
  Key Usage `keyCertSign`, MD2/MD5 refusal, SHA-1 warning, weak key-size warnings.
- Chain validation of intermediates against roots supplied in the same batch
  (`-SkipChainValidation` to opt out).
- Explicit store selection: `-StoreLocation` (`LocalMachine`/`CurrentUser`) and
  `-StoreName` (`Root`, `CA`, `AuthRoot`, `TrustedPeople`); automatic routing by
  certificate type.
- Idempotent store handling by SHA-256 fingerprint (`Imported`, `Replaced`,
  `AlreadyPresent`, `Skipped`, `WhatIf`, `Declined`).
- Structured reporting: `-PassThru` result objects, `-Json` envelope, `-LogFile`,
  `-LogLevel`, and CLI exit codes `0`, `1`, `2`.
- `-RequireConfirmation` for an explicit interactive yes/no prompt per certificate.
- Pester test suite (unit + gated integration tests), PSScriptAnalyzer configuration,
  GitHub Actions CI, and a release build script that produces a versioned ZIP with
  `SHA256SUMS.txt`.
- Documentation: `docs/SECURITY-MODEL.md`, `docs/EXAMPLES.md`, `SECURITY.md`,
  `CONTRIBUTING.md`, rewritten `README.md`, updated `AGENTS.md`, `VERSION` file.

### Changed

- **Breaking:** Root CA imports now require `-Thumbprint`; the 1.x behavior of importing
  whatever the URL returned is removed.
- **Breaking:** the CLI parameters `-RootUrl`/`-IntermediateUrl` are deprecated and mapped
  to `-Uri` with a warning; they will be removed in 3.0.0.
- **Breaking:** requirements corrected to Windows 10 1607+/Windows 11 and Windows Server
  2012 R2+ with PowerShell 7.4+; the unsupported Windows 7 claim was removed.
- **Breaking:** `-TempPath` now creates a unique subdirectory and only deletes that
  subdirectory (existing files are never deleted).
- Deduplication and replacement are based on the SHA-256 fingerprint; the SHA-1
  thumbprint is still reported for `certmgr.msc`/`certutil` compatibility.
- The wrapper accepts `-KeepFiles` as an alias of `-KeepTempFiles` for compatibility with
  the 1.x documentation.

### Removed

- The single-script-only implementation and the `main`-branch raw download as the
  recommended installation path; releases with checksums are now the supported channel.
- The misleading "securely downloading" claim without a verifiable fingerprint model.
- The 1.x README examples that used `http://` URLs.

### Security

- Plain HTTP URLs are rejected before any request is made.
- PFX/P12 files and any file containing a private key are refused.
- Root CA imports are protected by fingerprint pinning, high-impact confirmation
  (`ConfirmImpact = High`) and read-back verification of the store write.
- `-Force` no longer implies "import without checks": it only replaces a certificate with
  the same SHA-256 fingerprint.

## [1.0.0] - 2026-03-18

### Added

- Initial public version: a single PowerShell script that downloaded one Root CA and,
  optionally, one Intermediate CA from HTTPS URLs and imported them into
  `LocalMachine\Root` / `LocalMachine\CA`.
- `-Force`, `-KeepTempFiles`, `-WhatIf`/`-Confirm`, PEM/DER parsing, duplicate check by
  SHA-1 thumbprint, cleanup of the temporary directory.

[Unreleased]: https://github.com/paulmann/Import-CaCertificates/compare/v2.0.1...HEAD
[2.0.1]: https://github.com/paulmann/Import-CaCertificates/releases/tag/v2.0.1
[2.0.0]: https://github.com/paulmann/Import-CaCertificates/releases/tag/v2.0.0
[1.0.0]: https://github.com/paulmann/Import-CaCertificates/commits/main
