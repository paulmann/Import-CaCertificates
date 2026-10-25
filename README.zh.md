# Import-CaCertificates
[![版本](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates)
[![PowerShell](https://img.shields.io/badge/powershell-7.5%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![平台](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)

<!-- md-i18n:switcher -->
**其他语言：** [English](README.md) · [Deutsch](README.de.md) · 中文 · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

- [1. 概述](#1-概述)
- [2. 主要功能](#2-主要功能)
- [3. 系统要求](#3-系统要求)
- [4. 快速开始](#4-快速开始)
- [5. 安装与配置](#5-安装与配置)
- [6. 工作原理](#6-工作原理)
- [7. Let's Encrypt 集成指南](#7-lets-encrypt-集成指南)
- [8. 用法示例](#8-用法示例)
- [9. 参数参考](#9-参数参考)
- [10. 故障排查](#10-故障排查)
- [11. 许可证与致谢](#11-许可证与致谢)

***

## 1. 概述

**Import-CaCertificates** 是一款专业的 PowerShell 工具，用于自动下载根 CA 与中间 CA 证书并将其导入 Windows 证书存储区。它特别适用于防火墙后的服务器、自动化部署，以及修复 hMailServer 和 Exim 等邮件服务器中的“Unknown CA”错误。

### 主要用途
该脚本通过以下方式确保 Windows 环境信任所需的证书颁发机构：
- 通过直连 URL 安全下载证书。
- 将根 CA 导入 `Trusted Root Certification Authorities` 存储区。
- 将中间 CA 导入 `Intermediate Certification Authorities` 存储区。
- 提供干净、自动化的方式来保持信任链更新。

***

## 2. 主要功能

- ✨ **自动导入** - 一次处理根证书与中间证书。
- 🔍 **校验** - 导入前验证证书完整性。
- 🛠️ **管理安全** - 包含提权检查，确保权限正确。
- 🔄 **强制更新** - 可选择重新导入已有证书。
- 📂 **自动清理** - 除非另有指定，否则自动删除临时文件。
- 📝 **详细日志** - 在控制台逐步输出导入过程反馈。

***

## 3. 系统要求

- **操作系统**：Windows 7、Windows Server 2012 R2 或更高版本。
- **PowerShell**：7.5 或更高版本（支持 PowerShell Core 7.x）。
- **权限**：本地管理员权限（修改系统证书存储区所必需）。
- **网络**：可访问互联网，以便从源 URL 下载证书。

***

## 4. 快速开始

### 步骤 1：下载脚本
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/paulmann/Import-CaCertificates/main/Import-CaCertificates.ps1" -OutFile "Import-CaCertificates.ps1"
```

### 步骤 2：以管理员身份运行
以管理员身份打开 PowerShell 并执行：
```powershell
.\Import-CaCertificates.ps1 -RootUrl "https://example.com/root.crt" -IntermediateUrl "https://example.com/intermediate.crt"
```

***

## 5. 安装与配置

1. 克隆或下载此仓库。
2. 确保为当前会话配置了 `Set-ExecutionPolicy RemoteSigned`。
3. 将脚本放入你的工具目录（例如 `C:\Scripts\`）。

***

## 6. 工作原理

脚本按以下安全流程执行：
1. **权限检查**：验证脚本是否以管理员权限运行。
2. **环境准备**：为证书处理创建临时目录。
3. **下载阶段**：使用 `Invoke-WebRequest` 获取证书。
4. **导入阶段**：
   - 根证书 -> `LocalMachine\Root`
   - 中间证书 -> `LocalMachine\CA`
5. **清理**：删除临时文件与对象。

***

## 7. Let's Encrypt 集成指南

Let's Encrypt 证书通常需要让 Windows 服务（如 hMailServer 或 Exim）信任特定的根 CA 与中间 CA。

### 7.1 常用命令（Let's Encrypt ISRG Root X1）
要信任标准的 Let's Encrypt 证书链：
```powershell
.\Import-CaCertificates.ps1 `
    -RootUrl "https://letsencrypt.org/certs/isrgrootx1.pem" `
    -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-r3.pem"
```

### 7.2 高级／附加命令（交叉签名链）
适用于需要旧版 DST Root CA X3 交叉签名（用于兼容遗留系统）的环境：
```powershell
.\Import-CaCertificates.ps1 `
    -RootUrl "https://letsencrypt.org/certs/isrg-root-x2.pem" `
    -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-e1.pem" `
    -Force
```

***

## 8. 用法示例

### 仅导入根 CA
```powershell
.\Import-CaCertificates.ps1 -RootUrl "http://cacerts.digicert.com/DigiCertGlobalRootG2.crt"
```

### 导入并保留临时文件（用于调试）
```powershell
.\Import-CaCertificates.ps1 -RootUrl "..." -KeepFiles
```

***

## 9. 参数参考

| 参数 | 类型 | 必填 | 说明 |
|-----------|------|----------|-------------|
| `RootUrl` | String | **是** | 根 CA 证书文件的 URL（.crt、.cer、.pem）。 |
| `IntermediateUrl` | String | 否 | 中间 CA 证书文件的 URL。 |
| `Force` | Switch | 否 | 即使证书已存在也强制重新导入。 |
| `KeepFiles` | Switch | 否 | 完成后不删除临时文件。 |

***

## 10. 故障排查

- **错误：脚本必须以提权方式运行** - 右键单击 PowerShell 并选择“以管理员身份运行”。
- **hMailServer 报 Unknown CA** - 运行脚本后重启 hMailServer 服务，以加载新的受信任 CA。
- **下载失败** - 确认防火墙允许向证书提供商发起出站 HTTPS 请求。

***

## 11. 许可证与致谢

### 许可证
本项目采用 **PolyForm Noncommercial License 1.0.0** 授权。

### 版权
版权所有 © 2025 Mikhail Deynekin。
**作者**：Mikhail Deynekin
- **邮箱**：m@deynekin.com
- **GitHub**：[paulmann](https://github.com/paulmann)

***

## ⭐ 支持本项目
如果本工具帮助你解决了证书问题，欢迎在 GitHub 上为它点一个 star！
