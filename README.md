# Import-CaCertificates
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/powershell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)

- [1. Overview](#1-overview)
- [2. Key Features](#2-key-features)
- [3. System Requirements](#3-system-requirements)
- [4. Quick Start Guide](#4-quick-start-guide)
- [5. Installation & Setup](#5-installation--setup)
- [6. How It Works](#6-how-it-works)
- [7. Let's Encrypt Integration Guide](#7-lets-encrypt-integration-guide)
- [8. Usage Examples](#8-usage-examples)
- [9. Parameters Reference](#9-parameters-reference)
- [10. Troubleshooting](#10-troubleshooting)
- [11. License & Acknowledgments](#11-license--acknowledgments)

***

## 1. Overview

**Import-CaCertificates** is a professional PowerShell utility designed to automate the process of downloading and importing Root and Intermediate CA certificates into the Windows Certificate Store. This is particularly useful for servers behind firewalls, automated deployments, and fixing "Unknown CA" errors in mail servers like hMailServer and Exim.

### Primary Purpose
The script ensures that your Windows environment trusts the necessary Certificate Authorities by:
- Securely downloading certificates from direct URLs.
- Importing Root CAs into the `Trusted Root Certification Authorities` store.
- Importing Intermediate CAs into the `Intermediate Certification Authorities` store.
- Providing a clean, automated way to keep trust chains updated.

***

## 2. Key Features

- ✨ **Automated Import** - Handles both Root and Intermediate certificates in one pass.
- 🔍 **Validation** - Verifies certificate integrity before import.
- 🛠️ **Administrative Safety** - Includes elevation checks to ensure proper permissions.
- 🔄 **Forced Updates** - Option to re-import existing certificates.
- 📂 **Auto-Cleanup** - Automatically removes temporary files unless specified otherwise.
- 📝 **Detailed Logging** - Step-by-step console feedback on the import process.

***

## 3. System Requirements

- **Operating System**: Windows 7, Windows Server 2012 R2 or later.
- **PowerShell**: Version 5.1 or higher (PowerShell Core 7.x supported).
- **Permissions**: Local Administrator privileges (required to modify system certificate stores).
- **Network**: Internet access to download certificates from source URLs.

***

## 4. Quick Start Guide

### Step 1: Download the script
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/paulmann/Import-CaCertificates/main/Import-CaCertificates.ps1" -OutFile "Import-CaCertificates.ps1"
```

### Step 2: Run as Administrator
Open PowerShell as Administrator and execute:
```powershell
.\Import-CaCertificates.ps1 -RootUrl "https://example.com/root.crt" -IntermediateUrl "https://example.com/intermediate.crt"
```

***

## 5. Installation & Setup

1. Clone or download this repository.
2. Ensure `Set-ExecutionPolicy RemoteSigned` is configured for your session.
3. Place the script in your tools directory (e.g., `C:\Scripts\`).

***

## 6. How It Works

The script follows a secure execution flow:
1. **Privilege Check**: Validates that the script is running with administrative rights.
2. **Environment Setup**: Creates a temporary directory for certificate processing.
3. **Download Phase**: Fetches certificates using `Invoke-WebRequest`.
4. **Import Phase**: 
   - Root certificates -> `LocalMachine\Root`
   - Intermediate certificates -> `LocalMachine\CA`
5. **Cleanup**: Deletes temporary files and objects.

***

## 7. Let's Encrypt Integration Guide

Let's Encrypt certificates often require specific Root and Intermediate CAs to be trusted by Windows services (like hMailServer or Exim).

### 7.1 Typical Commands (Let's Encrypt ISRG Root X1)
To trust the standard Let's Encrypt chain:
```powershell
.\Import-CaCertificates.ps1 `
    -RootUrl "https://letsencrypt.org/certs/isrgrootx1.pem" `
    -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-r3.pem"
```

### 7.2 Advanced / Additional Commands (Cross-Signed Chains)
For environments requiring the older DST Root CA X3 cross-sign (for legacy compatibility):
```powershell
.\Import-CaCertificates.ps1 `
    -RootUrl "https://letsencrypt.org/certs/isrg-root-x2.pem" `
    -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-e1.pem" `
    -Force
```

***

## 8. Usage Examples

### Import only a Root CA
```powershell
.\Import-CaCertificates.ps1 -RootUrl "http://cacerts.digicert.com/DigiCertGlobalRootG2.crt"
```

### Import with temporary file retention (for debugging)
```powershell
.\Import-CaCertificates.ps1 -RootUrl "..." -KeepFiles
```

***

## 9. Parameters Reference

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `RootUrl` | String | **Yes** | URL to the Root CA certificate file (.crt, .cer, .pem). |
| `IntermediateUrl` | String | No | URL to the Intermediate CA certificate file. |
| `Force` | Switch | No | Force re-import of certificates even if already present. |
| `KeepFiles` | Switch | No | Do not delete temporary files after completion. |

***

## 10. Troubleshooting

- **Error: Script must be run elevated** - Right-click PowerShell and "Run as Administrator".
- **Unknown CA in hMailServer** - After running the script, restart the hMailServer service to pick up the new trusted CAs.
- **Download Failed** - Ensure your firewall allows outbound HTTPS requests to the certificate provider.

***

## 11. License & Acknowledgments

### License
This project is licensed under the **MIT License**.

### Copyright
Copyright © 2025 Mikhail Deynekin.
**Author**: Mikhail Deynekin
- **Email**: m@deynekin.com
- **GitHub**: [paulmann](https://github.com/paulmann)

***

## ⭐ Support the Project
If this tool helped you resolve certificate issues, please give it a star on GitHub!
