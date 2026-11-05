# Development

This chapter covers the repository layout, the test and analysis gates, CI, and the release build. It is the
manual's version of
[CONTRIBUTING.md](../CONTRIBUTING.md) and
[AGENTS.md](../AGENTS.md); those files are the
contract, this page is the practical walkthrough.

## Repository layout

| Path | Purpose |
|---|---|
| `Import-CaCertificates.ps1` | CLI wrapper; loads the module from `src/` relative to itself, maps exceptions to exit codes |
| `src/Import-CaCertificates/` | Module manifest (`.psd1`) and implementation (`.psm1`) |
| `tests/` | Pester unit tests, gated integration tests, shared helpers (`Helpers.ps1`) |
| `tools/New-Release.ps1` | Builds the release ZIP and `SHA256SUMS.txt` |
| `docs/` | Security model and task examples |
| `PSScriptAnalyzerSettings.psd1` | Static-analysis configuration |
| `.github/workflows/` | `ci.yml` (lint + tests) and `release.yml` (tag-driven release) |
| `VERSION` | Current version, `2.0.1`, mirrored in the manifest and the README badge |
| `wiki/` | Sources of this wiki plus `wiki.json`; built and verified with `ghagent` |

## Requirements

- Windows 10/11 or Windows Server 2012 R2+ for running the tests.
- PowerShell 7.4 or later (`pwsh`), enforced by `#Requires -Version 7.4`.
- Pester 5.7.1 or 6.x (CI pins 5.7.1).
- PSScriptAnalyzer 1.25 or later (CI pins 1.25.0).
- Git.

Install the test dependencies:

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Force -Scope CurrentUser
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
```

## Tests

```powershell
Invoke-Pester -Path .\tests -Output Detailed
```

The suite contains **38 Pester tests: 33 unit tests and 5 integration tests**, counted from the `It` blocks
in `tests/Import-CaCertificates.Unit.Tests.ps1` and `tests/Import-CaCertificates.Integration.Tests.ps1`. On a
non-elevated local machine the recorded result is **36 passed and 2 skipped**: the skipped tests are the
network test (runs when `$env:CI` is set) and the elevated `LocalMachine` test (runs only when CI is on an
elevated Windows runner).

The unit suite needs no administrator rights and no network. It generates throw-away certificate authorities
in a temporary directory, writes to `CurrentUser\CA`, and removes what it created. It covers the module
surface, thumbprint normalization, file parsing (PEM, DER, multi-certificate bundle, private-key and PFX
refusal, directories), certificate policy, idempotent and `-Force` store behaviour, trust refusals, the JSON
envelope, log files and the wrapper exit codes.

Integration tests are gated on purpose:

- network test: `-Skip:(-not $script:IntegrationCi)`, so it runs when `$env:CI` is set;
- elevated `LocalMachine` test: `-Skip:(-not ($script:IntegrationCi -and $script:IntegrationAdmin))`;
- non-admin refusal test: `-Skip:($script:IntegrationAdmin)`, so it only runs when the session is not
  elevated.

Do not enable a gate just to make a test pass. Cover the same behaviour with `-WhatIf` or
`-StoreLocation CurrentUser`.

## Static analysis

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

The settings file enables the default rules at `Error` and `Warning` severity and excludes exactly one rule,
`PSUseShouldProcessForStateChangingFunctions`, because the test helpers create throw-away certificates by
design. Expected output: no rows. CI installs PSScriptAnalyzer **1.25.0** and fails the build if any result
is returned.

## Continuous integration

[ci.yml](https://github.com/paulmann/Import-CaCertificates/blob/main/.github/workflows/ci.yml) runs on every
push to `main`, every `v*` tag and every pull request, plus manual dispatch:

| Job | Runner | What it does |
|---|---|---|
| `lint` | `ubuntu-latest` | Installs PSScriptAnalyzer 1.25.0, runs `Invoke-ScriptAnalyzer` with the repository settings, fails on any finding |
| `test` | `windows-latest` | Shows `$PSVersionTable`, installs Pester 5.7.1, validates the module manifest with `Test-ModuleManifest`, runs `Invoke-Pester` with `CI=true`, fails on any failed test |

The `CI=true` environment variable is what enables the network integration test. The release workflow only
starts from a `v*` tag or a manual dispatch.

## Build a release archive locally

```powershell
.\tools\New-Release.ps1 -Version v2.0.1 -OutputDirectory .\out
```

The script validates the version format, refuses a version that does not match the module manifest
`ModuleVersion`, checks that the required files exist, stages them, and writes:

- `out\Import-CaCertificates-2.0.1.zip`;
- `out\SHA256SUMS.txt`, containing `<sha256>  <filename>`, UTF-8 without BOM.

It prints the archive path, the checksum path and the archive size, and returns an object with
`Version`, `ArchivePath`, `ChecksumPath` and `ArchiveBytes`. The archive contains the wrapper, all
`README*.md` files, `LICENSE`, `CHANGELOG.md`, `SECURITY.md`, `CONTRIBUTING.md`, and the `src/` and `docs/`
directories.

Confirm the archive before it leaves your machine:

```powershell
Get-Content .\out\SHA256SUMS.txt
(Get-FileHash -Algorithm SHA256 -LiteralPath .\out\Import-CaCertificates-2.0.1.zip).Hash
```

## Release workflow

[release.yml](https://github.com/paulmann/Import-CaCertificates/blob/main/.github/workflows/release.yml) runs
on a `v*` tag or manual dispatch on `windows-latest`:

1. checks out the tag;
2. runs `tools/New-Release.ps1 -Version <tag> -OutputDirectory ./out`;
3. re-reads `SHA256SUMS.txt` and verifies every listed checksum, failing on a mismatch;
4. creates the release if it does not exist and uploads the assets with `gh release upload --clobber`,
   using release notes that point at `CHANGELOG.md`.

The version bump procedure (from `CONTRIBUTING.md`) is: update `VERSION`, the manifest `ModuleVersion`,
`CHANGELOG.md` and the README version badge; run tests and the linter on Windows; commit and push `main`;
create and push an annotated tag; let the workflow build and publish; then download the archive, verify its
checksum, extract it and run a `-WhatIf` import.

## Code style and contribution rules

- PowerShell 7.4+ only: `#Requires -Version 7.4`, `Set-StrictMode -Version Latest`,
  `$ErrorActionPreference = 'Stop'`.
- Approved verbs; comment-based help for public commands.
- No `Write-Host`: use the information, verbose and warning streams and the module's logging helper so
  `-LogFile` keeps working.
- Do not call `exit` from module code: throw exceptions carrying `Data['CaExitCode']` and let the wrapper map
  them.
- Keep the module free of PSScriptAnalyzer findings.
- Files are UTF-8 without BOM with LF line endings.
- Conventional commits, for example `feat(module): add multi-certificate PEM parsing`,
  `fix(wrapper): map -KeepFiles alias to -KeepTempFiles`, `docs(readme): document the SHA-256 requirement`.
- One logical change per pull request, tests that fail without the change, and a CHANGELOG entry under
  `[Unreleased]`. Changes touching validation, fingerprint handling, store writes or confirmation need a
  security-review section in the pull request.

Do not weaken the security defaults: a pull request that removes the fingerprint requirement, allows HTTP or
imports private keys is rejected. Never put real certificates, private keys, internal CA thumbprints,
production hostnames or production logs into issues, pull requests or test data. The repository contract is
in [CONTRIBUTING.md](../CONTRIBUTING.md) and
[AGENTS.md](../AGENTS.md).

## Building this wiki

The wiki sources live in `wiki/` with a `wiki.json` manifest; `_Sidebar.md` and `_Footer.md` are generated.
From a checkout of the wiki tooling:

```bash
python tools/ghagent.py wiki build --root <repository> --out <build-dir>
python tools/ghagent.py wiki verify --root <repository> --out <build-dir>
```

Publication is a separate, explicit step (`ghagent wiki publish --repo paulmann/Import-CaCertificates
--push`); a missing `--push` is a dry run.

Related chapters: [Parameters](05-Parameters.md) for the public contract a change must keep,
[Security Model](06-Security-Model.md) for the security review a sensitive pull request needs, and
[Migration from 1.x](08-Migration-from-1.x.md) when a release changes user-visible behaviour.
