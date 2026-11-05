#Requires -Version 7.4
<#
.SYNOPSIS
    Builds the release archive and SHA-256 checksums for Import-CaCertificates.

.DESCRIPTION
    Assembles a versioned ZIP archive containing the module, the CLI wrapper, the
    documentation and the license, then writes SHA256SUMS.txt next to it. Used by
    the release workflow and runnable locally:

        pwsh -NoProfile -File ./tools/New-Release.ps1 -Version v2.0.0

    The manifest version must match the requested version; this prevents tagging a
    release that does not contain the code it claims to.

.PARAMETER Version
    Release version, with or without a leading "v" (for example 2.0.0 or v2.0.0).

.PARAMETER OutputDirectory
    Directory for the archive and checksum file. Created if missing.

.OUTPUTS
    PSCustomObject describing the archive and checksum file paths.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Version,

    [Parameter()]
    [string]$OutputDirectory = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'out')
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$versionNumber = $Version.TrimStart([char[]]@('v', 'V'))

if ($versionNumber -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Invalid version '$Version': expected a semantic version such as 2.0.0."
}

$manifestPath = Join-Path -Path $repositoryRoot -ChildPath 'src/Import-CaCertificates/Import-CaCertificates.psd1'
$manifest = Import-PowerShellDataFile -Path $manifestPath
if ($manifest.ModuleVersion -ne $versionNumber) {
    throw "Version mismatch: manifest declares $($manifest.ModuleVersion) but the release requests $versionNumber."
}

$requiredFiles = @(
    'Import-CaCertificates.ps1',
    'README.md',
    'LICENSE',
    'CHANGELOG.md',
    'SECURITY.md',
    'CONTRIBUTING.md'
)
foreach ($file in $requiredFiles) {
    $path = Join-Path -Path $repositoryRoot -ChildPath $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required release file '$file' is missing."
    }
}

$stagingDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("CaRelease_{0}" -f [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -Path $stagingDirectory -ItemType Directory -ErrorAction Stop

try {
    foreach ($file in $requiredFiles) {
        Copy-Item -LiteralPath (Join-Path -Path $repositoryRoot -ChildPath $file) -Destination $stagingDirectory
    }

    foreach ($directory in @('src', 'docs')) {
        $source = Join-Path -Path $repositoryRoot -ChildPath $directory
        if (Test-Path -LiteralPath $source -PathType Container) {
            Copy-Item -LiteralPath $source -Destination $stagingDirectory -Recurse
        }
    }

    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
    $archiveName = "Import-CaCertificates-$versionNumber.zip"
    $archivePath = Join-Path -Path $OutputDirectory -ChildPath $archiveName

    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    Compress-Archive -Path (Join-Path -Path $stagingDirectory -ChildPath '*') -DestinationPath $archivePath -CompressionLevel Optimal

    $checksumTargets = @(
        (Join-Path -Path $OutputDirectory -ChildPath $archiveName),
        (Join-Path -Path $repositoryRoot -ChildPath 'Import-CaCertificates.ps1'),
        (Join-Path -Path $repositoryRoot -ChildPath 'src/Import-CaCertificates/Import-CaCertificates.psm1'),
        (Join-Path -Path $repositoryRoot -ChildPath 'src/Import-CaCertificates/Import-CaCertificates.psd1')
    )

    $checksumFile = Join-Path -Path $OutputDirectory -ChildPath 'SHA256SUMS.txt'
    $lines = foreach ($target in $checksumTargets) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
        "{0}  {1}" -f $hash, (Split-Path -Path $target -Leaf)
    }
    [System.IO.File]::WriteAllLines($checksumFile, $lines, [System.Text.UTF8Encoding]::new($false))

    Write-Information -MessageData "Release archive: $archivePath" -InformationAction Continue
    Write-Information -MessageData "Checksums:       $checksumFile" -InformationAction Continue

    return [pscustomobject]@{
        Version        = $versionNumber
        ArchivePath    = $archivePath
        ChecksumPath   = $checksumFile
        ArchiveBytes   = (Get-Item -LiteralPath $archivePath).Length
    }
}
finally {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
