# Import-CaCertificates
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates)
[![PowerShell](https://img.shields.io/badge/powershell-7.5%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Plattform](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)

<!-- md-i18n:switcher -->
**In anderen Sprachen:** [English](README.md) · Deutsch · [中文](README.zh.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

- [1. Überblick](#1-überblick)
- [2. Hauptfunktionen](#2-hauptfunktionen)
- [3. Systemanforderungen](#3-systemanforderungen)
- [4. Schnellstart](#4-schnellstart)
- [5. Installation & Einrichtung](#5-installation--einrichtung)
- [6. Funktionsweise](#6-funktionsweise)
- [7. Let's Encrypt: Integrationsanleitung](#7-lets-encrypt-integrationsanleitung)
- [8. Anwendungsbeispiele](#8-anwendungsbeispiele)
- [9. Parameterreferenz](#9-parameterreferenz)
- [10. Fehlerbehebung](#10-fehlerbehebung)
- [11. Lizenz & Danksagung](#11-lizenz--danksagung)

***

## 1. Überblick

**Import-CaCertificates** ist ein professionelles PowerShell-Werkzeug, das das Herunterladen und Importieren von Root- und Intermediate-CA-Zertifikaten in den Windows-Zertifikatspeicher automatisiert. Das ist besonders nützlich für Server hinter Firewalls, für automatisierte Bereitstellungen und zur Behebung von Fehlern „Unbekannte CA“ in Mailservern wie hMailServer und Exim.

### Hauptzweck
Das Skript stellt sicher, dass Ihre Windows-Umgebung den erforderlichen Zertifizierungsstellen vertraut, indem es:
- Zertifikate sicher über direkte URLs herunterlädt.
- Root-CAs in den Speicher `Trusted Root Certification Authorities` importiert.
- Intermediate-CAs in den Speicher `Intermediate Certification Authorities` importiert.
- Einen sauberen, automatisierten Weg bietet, um Vertrauensketten aktuell zu halten.

***

## 2. Hauptfunktionen

- ✨ **Automatischer Import** - verarbeitet sowohl Root- als auch Intermediate-Zertifikate in einem Durchgang.
- 🔍 **Validierung** - prüft die Integrität der Zertifikate vor dem Import.
- 🛠️ **Absicherung für administrative Rechte** - enthält eine Rechteprüfung, die die erforderlichen Berechtigungen sicherstellt.
- 🔄 **Erzwungene Aktualisierung** - Option, vorhandene Zertifikate erneut zu importieren.
- 📂 **Automatische Bereinigung** - entfernt temporäre Dateien automatisch, sofern nichts anderes angegeben ist.
- 📝 **Detaillierte Protokollierung** - Schritt-für-Schritt-Rückmeldungen in der Konsole zum Importvorgang.

***

## 3. Systemanforderungen

- **Betriebssystem**: Windows 7, Windows Server 2012 R2 oder neuer.
- **PowerShell**: Version 7.5 oder höher (PowerShell Core 7.x wird unterstützt).
- **Berechtigungen**: lokale Administratorrechte (erforderlich, um die systemweiten Zertifikatspeicher zu ändern).
- **Netzwerk**: Internetzugriff, um Zertifikate von den Quell-URLs herunterzuladen.

***

## 4. Schnellstart

### Schritt 1: Skript herunterladen
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/paulmann/Import-CaCertificates/main/Import-CaCertificates.ps1" -OutFile "Import-CaCertificates.ps1"
```

### Schritt 2: Als Administrator ausführen
PowerShell als Administrator öffnen und ausführen:
```powershell
.\Import-CaCertificates.ps1 -RootUrl "https://example.com/root.crt" -IntermediateUrl "https://example.com/intermediate.crt"
```

***

## 5. Installation & Einrichtung

1. Dieses Repository klonen oder herunterladen.
2. Sicherstellen, dass `Set-ExecutionPolicy RemoteSigned` für Ihre Sitzung konfiguriert ist.
3. Das Skript in Ihr Werkzeugverzeichnis legen (z. B. `C:\Scripts\`).

***

## 6. Funktionsweise

Das Skript folgt einem sicheren Ausführungsablauf:
1. **Rechteprüfung**: prüft, ob das Skript mit administrativen Rechten ausgeführt wird.
2. **Einrichtung der Umgebung**: erstellt ein temporäres Verzeichnis für die Zertifikatsverarbeitung.
3. **Download-Phase**: ruft die Zertifikate mit `Invoke-WebRequest` ab.
4. **Import-Phase**: 
   - Root-Zertifikate -> `LocalMachine\Root`
   - Intermediate-Zertifikate -> `LocalMachine\CA`
5. **Bereinigung**: löscht temporäre Dateien und Objekte.

***

## 7. Let's Encrypt: Integrationsanleitung

Let's-Encrypt-Zertifikate erfordern häufig bestimmte Root- und Intermediate-CAs, denen Windows-Dienste (wie hMailServer oder Exim) vertrauen müssen.

### 7.1 Typische Befehle (Let's Encrypt ISRG Root X1)
Um der Standardkette von Let's Encrypt zu vertrauen:
```powershell
.\Import-CaCertificates.ps1 `
    -RootUrl "https://letsencrypt.org/certs/isrgrootx1.pem" `
    -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-r3.pem"
```

### 7.2 Erweiterte / zusätzliche Befehle (Cross-Signed-Ketten)
Für Umgebungen, die die ältere Cross-Signatur von DST Root CA X3 benötigen (für Kompatibilität mit Altbeständen):
```powershell
.\Import-CaCertificates.ps1 `
    -RootUrl "https://letsencrypt.org/certs/isrg-root-x2.pem" `
    -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-e1.pem" `
    -Force
```

***

## 8. Anwendungsbeispiele

### Nur eine Root-CA importieren
```powershell
.\Import-CaCertificates.ps1 -RootUrl "http://cacerts.digicert.com/DigiCertGlobalRootG2.crt"
```

### Import mit Beibehaltung der temporären Dateien (zur Fehlersuche)
```powershell
.\Import-CaCertificates.ps1 -RootUrl "..." -KeepFiles
```

***

## 9. Parameterreferenz

| Parameter | Typ | Erforderlich | Beschreibung |
|-----------|------|----------|-------------|
| `RootUrl` | String | **Ja** | URL zur Zertifikatsdatei der Root-CA (.crt, .cer, .pem). |
| `IntermediateUrl` | String | Nein | URL zur Zertifikatsdatei der Intermediate-CA. |
| `Force` | Switch | Nein | Erzwingt den erneuten Import der Zertifikate, auch wenn sie bereits vorhanden sind. |
| `KeepFiles` | Switch | Nein | Temporäre Dateien nach Abschluss nicht löschen. |

***

## 10. Fehlerbehebung

- **Fehler: Skript muss mit erhöhten Rechten ausgeführt werden** - mit der rechten Maustaste auf PowerShell klicken und "Als Administrator ausführen" wählen.
- **Unbekannte CA in hMailServer** - nach dem Ausführen des Skripts den Dienst hMailServer neu starten, damit die neuen vertrauenswürdigen CAs übernommen werden.
- **Download fehlgeschlagen** - sicherstellen, dass Ihre Firewall ausgehende HTTPS-Anfragen an den Zertifikatsanbieter zulässt.

***

## 11. Lizenz & Danksagung

### Lizenz
Dieses Projekt ist unter der **PolyForm Noncommercial License 1.0.0** lizenziert.

### Copyright
Copyright © 2025 Mikhail Deynekin.
**Autor**: Mikhail Deynekin
- **E-Mail**: m@deynekin.com
- **GitHub**: [paulmann](https://github.com/paulmann)

***

## ⭐ Das Projekt unterstützen
Wenn Ihnen dieses Werkzeug geholfen hat, Zertifikatsprobleme zu lösen, geben Sie ihm bitte einen Stern auf GitHub!
