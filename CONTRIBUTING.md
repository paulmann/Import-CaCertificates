# Contributing

Thanks for considering a contribution. This project is a security-sensitive PowerShell
tool, so changes are reviewed for correctness and failure modes before anything else.

## Before you start

- Open an issue for anything larger than a typo or a documentation fix, especially if
  it changes parameters, defaults or trust behavior.
- Never include real certificates, private keys, thumbprints of internal CAs, hostnames
  or logs from production systems in issues, pull requests or test data.
- Do not weaken the security defaults. A pull request that removes the mandatory
  fingerprint check, allows HTTP, or imports private keys will be rejected.

## Requirements

- Windows 10/11 or Windows Server 2012 R2+ for running the tests.
- PowerShell 7.4 or later (`pwsh`).
- Pester 5.7.1 or 6.x.
- PSScriptAnalyzer 1.25 or later.
- Git.

Install the test dependencies:

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Force -Scope CurrentUser
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
```

## Repository layout

| Path | Purpose |
|---|---|
| `Import-CaCertificates.ps1` | CLI wrapper; loads the module from `src/` |
| `src/Import-CaCertificates/` | Module manifest and implementation |
| `tests/` | Pester unit and gated integration tests, shared helpers |
| `tools/New-Release.ps1` | Builds the release ZIP and `SHA256SUMS.txt` |
| `docs/` | Security model and examples |
| `PSScriptAnalyzerSettings.psd1` | Static analysis configuration |
| `.github/workflows/` | CI and release workflows |

## Development workflow

1. Create a branch from `main`.
2. Make the change; add or update tests that fail without it.
3. Run the full suite and the linter:

   ```powershell
   Invoke-Pester -Path .\tests -Output Detailed
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
   ```

4. Update `CHANGELOG.md` under `[Unreleased]`.
5. Update documentation if parameters, defaults or behavior changed.
6. Open a pull request that explains the problem, the change and how it was tested.

Integration tests are gated: network tests run only when `$env:CI` is set, and
LocalMachine store tests run only on an elevated CI runner. Do not enable them in a pull
request just to make a test pass; write a unit test with `-WhatIf` or
`-StoreLocation CurrentUser` instead.

## Code style

- PowerShell 7.4+ only: `#Requires -Version 7.4`, `Set-StrictMode -Version Latest`,
  `$ErrorActionPreference = 'Stop'`.
- Approved verbs for functions; comment-based help for public commands.
- No `Write-Host`; use the information/verbose/warning streams and the module's logging
  helper so `-LogFile` keeps working.
- Do not call `exit` from module code; throw exceptions carrying
  `Data['CaExitCode']` and let the CLI wrapper map them to exit codes.
- Keep the module free of PSScriptAnalyzer warnings.
- Files are UTF-8 without BOM with LF line endings.

## Commit messages

Use the conventional style already used in the repository:

```
feat(module): add multi-certificate PEM parsing
fix(wrapper): map -KeepFiles alias to -KeepTempFiles
docs(readme): document the SHA-256 requirement
test(unit): cover chain mismatch refusal
chore(release): prepare 2.0.1 archive
```

## Security review

Changes that touch validation, fingerprint handling, store writes, download handling or
confirmation logic need an explicit section in the pull request:

- what can now be written, and to which store;
- what is verified before the write;
- how the change behaves in a non-interactive session;
- how a failed verification is reported (exit code and message).

## Release process

1. Update `VERSION`, the module manifest `ModuleVersion`, `CHANGELOG.md` and the README
   version badge.
2. Run the full test suite and the linter on Windows.
3. Commit and push `main`.
4. Tag the release: `git tag -a v2.0.1 -m "Import-CaCertificates 2.0.1"` and push the tag.
5. The release workflow builds `Import-CaCertificates-2.0.1.zip`, verifies the archive
   checksum and publishes the GitHub release with `SHA256SUMS.txt`.
6. Verify the published assets: download the archive, check the checksum, extract it and
   run a `-WhatIf` import.

## License

By contributing you agree that your contribution is licensed under the **MIT License**
(see `LICENSE`). This project is distributed under MIT; contributions are accepted under
the same terms.
