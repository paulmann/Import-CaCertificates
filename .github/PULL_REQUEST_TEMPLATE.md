## Summary

What changes, and why?

## Type of change

- [ ] Bug fix
- [ ] Feature
- [ ] Documentation
- [ ] CI / build / release
- [ ] Security (validation, fingerprint handling, store writes, download handling)

## Verification

- [ ] `Invoke-Pester -Path .\tests -Output Detailed` passes (38 tests: 33 unit + 5 integration)
- [ ] `Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` reports nothing
- [ ] New or updated tests cover the change without `-AllowUnverifiedRoot`
- [ ] A dry run was executed: `Import-CaCertificate ... -WhatIf -Confirm:$false`
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`
- [ ] Documentation updated if parameters, defaults or behaviour changed
- [ ] No secrets, private keys, PFX files, internal CA certificates or personal data in the diff
- [ ] Files stay UTF-8 without BOM with LF line endings (`.editorconfig`, `.gitattributes`)

## Security review

Required when validation, fingerprint handling, store writes, download handling or
confirmation logic changes. State each point in one line:

- what can now be written, and to which store:
- what is verified before the write:
- behaviour in a non-interactive session (`-Confirm:$false`):
- how a failed verification is reported (message, exit code `1` or `2`):

## Release impact

- [ ] No release needed
- [ ] Patch / minor / major release required (explain)
- [ ] Breaking change for 2.x users (explain in the body and in `CHANGELOG.md`)
- [ ] Release archive or `SHA256SUMS.txt` build affected (explain)
