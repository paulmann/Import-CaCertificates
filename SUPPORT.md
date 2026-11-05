# Support

## Where to ask

| Question | Where |
|---|---|
| An import fails, or the exit code does not match the documentation | [Issues — choose a form](https://github.com/paulmann/Import-CaCertificates/issues/new/choose), bug report |
| A parameter, check or store assignment should work differently | [Issues — choose a form](https://github.com/paulmann/Import-CaCertificates/issues/new/choose), feature request |
| A vulnerability, or a way past the fingerprint pin | privately, per [SECURITY.md](SECURITY.md); never a public issue |
| How to use the module in a runbook or on a specific service | [docs/EXAMPLES.md](docs/EXAMPLES.md) and [docs/AGENT-GUIDE.md](docs/AGENT-GUIDE.md) |
| What the tool protects and what it deliberately does not | [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md) |
| Why a version or platform is not supported | [README.md](README.md), sections "Requirements" and "Migration from 1.x" |

## What to include

- the affected version: the release tag, `VERSION`, or `(Get-Module Import-CaCertificates).Version`;
- the Windows build (`[Environment]::OSVersion.Version`) and the PowerShell version
  (`$PSVersionTable.PSVersion`);
- the command in full, with secrets and internal host names redacted, and its exit code;
- the `-Json` envelope or the `-LogFile` lines, with personal data removed;
- whether the session was elevated and which `-StoreLocation` was used.

Remove private keys, PFX files, internal CA certificates, internal thumbprints and any
production log before posting. A public CA certificate and its published fingerprint are
not secrets; an internal one is.

## What to expect

| Version | Supported |
|---|---|
| 2.x | Yes, current release line |
| 1.x | No; replaced by 2.0.0, because Root CA imports could be made without fingerprint verification |

The project is maintained by one person, so answers are not instant. An accepted bug is
recorded in the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md) when the fix lands,
not when the issue is opened.

## Security problems

Do not open an issue for a security problem. Follow [SECURITY.md](SECURITY.md): the
repository's Security tab accepts a private report, and the disclosure timeline is stated
there.
