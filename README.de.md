# Import-CaCertificates

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates/releases/latest)
[![PowerShell](https://img.shields.io/badge/powershell-7.4%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-lightgrey.svg)](LICENSE)

<!-- md-i18n:switcher -->
**Dieses Dokument lesen in:** [English](README.md) · **Deutsch** · [中文](README.zh.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

- [1. Überblick](#1-überblick)
- [2. Was sich in 2.0.0 geändert hat](#2-was-sich-in-200-geändert-hat)
- [3. Funktionen](#3-funktionen)
- [4. Sicherheitsmodell](#4-sicherheitsmodell)
- [5. Anforderungen](#5-anforderungen)
- [6. Installation](#6-installation)
- [7. Schnellstart](#7-schnellstart)
- [8. Anwendungsbeispiele](#8-anwendungsbeispiele)
- [9. Parameter](#9-parameter)
- [10. Importergebnisse und Exit-Codes](#10-importergebnisse-und-exit-codes)
- [11. Migration von 1.x](#11-migration-von-1x)
- [12. Fehlerbehebung](#12-fehlerbehebung)
- [13. Entwicklung](#13-entwicklung)
- [14. Lizenz und Support](#14-lizenz-und-support)

***

## 1. Überblick

**Import-CaCertificates** importiert öffentliche CA-Zertifikate (Root und Intermediate) in
Windows-Zertifikatspeicher. Es ist für Server hinter restriktiven Firewalls und für
Umgebungen gedacht, die einer bestimmten CA-Kette vertrauen müssen — zum Beispiel hMailServer,
Exim unter Windows, IIS oder eine interne Unternehmens-PKI.

Das Werkzeug ist bewusst eng gefasst: Es lädt öffentliche Zertifikate herunter oder liest
sie aus Dateien, prüft, dass es die erwarteten Zertifikate sind, und importiert sie in
`LocalMachine`- oder `CurrentUser`-Speicher. Es fordert keine Zertifikate an, erneuert, sichert, listet
oder entfernt sie nicht und importiert niemals private Schlüssel.

Das Importieren einer Root-CA ist eine maschinenweite Vertrauensentscheidung. Version 2.0.0 verlangt
daher für jedes importierte Zertifikat einen erwarteten SHA-256-Fingerabdruck und verweigert einen Root-CA-Import
ohne diesen, sofern nicht der ausdrückliche Schalter `-AllowUnverifiedRoot` verwendet wird.

## 2. Was sich in 2.0.0 geändert hat

Version 2.0.0 ist eine sicherheitsorientierte Neufassung. Das Verhalten des Befehls hat sich
absichtlich geändert; siehe [CHANGELOG.md](CHANGELOG.md) und
[Migration von 1.x](#11-migration-von-1x), bevor Sie aktualisieren.

- Das einzelne Skript wurde zu einem Modul (`Import-CaCertificate`) plus einem dünnen CLI-Wrapper.
- Root-CA-Importe erfordern einen festgelegten SHA-256-Fingerabdruck; der alte Ablauf nur mit
  `-RootUrl` wird verweigert, statt stillschweigend vertraut zu werden.
- Reine HTTP-URLs, PFX-/P12-Dateien und Dateien mit privaten Schlüsseln werden abgelehnt.
- Zertifikate werden validiert (Gültigkeitszeitraum, CA-Rolle, Key Usage, Signaturalgorithmus),
  und ein Root-/Intermediate-Paar wird vor dem Import auf die Kette geprüft.
- Mehrzertifikat-PEM-Bündel, lokale Dateien und Verzeichnisse werden unterstützt.
- Die Deduplizierung verwendet den SHA-256-Fingerabdruck (der SHA-1-Thumbprint wird gemeldet, ist
  aber nicht die Identitätsprüfung).
- Strukturierte Ergebnisse (`-PassThru`), JSON-Berichte (`-Json`), Protokolldateien (`-LogFile`),
  Exit-Codes sowie Pester-/PSScriptAnalyzer-CI kamen hinzu.

## 3. Funktionen

- **Ausdrückliche Vertrauensanker**: Jedes importierte Zertifikat muss zu einem erwarteten
  SHA-256-Fingerabdruck passen, der mit `-Thumbprint` übergeben wird.
- **Sichere Standardeinstellungen für Root-CAs**: Ein Root-CA-Import ohne Fingerabdruck wird verweigert;
  `-AllowUnverifiedRoot` ist die ausdrückliche, deutlich gemeldete Ausnahme.
- **Nur HTTPS**: `http://`-URLs werden abgelehnt, bevor eine Anfrage erfolgt.
- **Nur öffentliche Zertifikate**: PFX-/P12-Dateien und jede Datei mit einem privaten Schlüssel
  werden abgelehnt.
- **Validierung**: X.509-Parsing, `NotBefore`/`NotAfter`, Basic Constraints `CA=true`,
  Key Usage `keyCertSign`, defekte Signaturalgorithmen (MD2/MD5) und schwache Schlüssellängen.
- **Kettenvalidierung**: Wenn eine Root und ein Intermediate im selben Lauf ankommen, muss der
  Intermediate zur übergebenen Root passen (`-SkipChainValidation` zum Abwählen).
- **Flexible Eingabe**: HTTPS-URL, lokale PEM-/DER-Datei, Base64-DER, Mehrzertifikat-PEM-Bündel
  oder ein Verzeichnis mit Zertifikatsdateien.
- **Idempotente Speicher-Schreibvorgänge**: Ein Zertifikat mit demselben SHA-256-Fingerabdruck wird
  übersprungen; `-Force` ersetzt eine vorhandene Kopie, überspringt aber nie die Prüfung.
- **Automatisierungsfreundlich**: `-WhatIf`, `-Confirm`, `-PassThru`, `-Json`, `-LogFile`,
  `-LogLevel` und eigene Exit-Codes.
- **Windows-Speicher**: `LocalMachine` (Standard, erhöhte Rechte) und `CurrentUser`, Speicher
  `Root`, `CA`, `AuthRoot` und `TrustedPeople`.

## 4. Sicherheitsmodell

Das vollständige Bedrohungsmodell steht in [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md). Die kurze
Fassung:

1. **Nur HTTPS** wird für Downloads akzeptiert.
2. **Der erwartete SHA-256-Fingerabdruck ist Pflicht** für jedes importierte Zertifikat.
   Für eine Root-CA ist er Pflicht, sofern nicht `-AllowUnverifiedRoot` ausdrücklich übergeben wird.
3. **Das Zertifikat wird vor jedem Schreiben in den Speicher validiert**: als X.509 geparst, innerhalb seines
   Gültigkeitszeitraums, als CA markiert, zum Signieren von Zertifikaten berechtigt und mit einem
   akzeptablen Algorithmus signiert.
4. **Das Zertifikat ist kein privater Schlüssel**: Dateien, die private Schlüssel enthalten, und
   PFX-/P12-Container werden abgelehnt.
5. **Bestätigung ist der Standard**: `ConfirmImpact = High` bedeutet, dass ein interaktiver Lauf
   vor dem Schreiben fragt; nicht interaktive Automatisierung muss `-Confirm:$false` übergeben.
6. **Keine Telemetrie, kein versteckter Netzwerkzugriff**: Die einzigen Netzwerkanfragen sind die
   von Ihnen angegebenen `-Uri`-Werte.

Ein festgelegter Fingerabdruck schützt gegen einen ausgetauschten Download, einen kompromittierten Mirror oder
eine falsche Datei. Er schützt nicht gegen eine CA, die legitim eine andere Root neu ausgestellt hat — deshalb
muss der Fingerabdruck von der eigenen veröffentlichten Seite der CA oder aus Ihrer PKI-Dokumentation stammen
und nicht von derselben URL, von der Sie herunterladen.

## 5. Anforderungen

| Anforderung | Details |
|---|---|
| Betriebssystem | Windows 10 (1607 oder später), Windows 11, Windows Server 2012 R2 oder später |
| PowerShell | 7.4 oder später (`pwsh`). Windows PowerShell 5.1 wird nicht unterstützt. |
| Berechtigungen | Lokaler Administrator für `-StoreLocation LocalMachine`; keine Erhöhung für `-StoreLocation CurrentUser` |
| Netzwerk | HTTPS-Zugriff auf jeden `-Uri`-Host; mit `-Path` nicht erforderlich |
| Windows 7 / 8.1 | Nicht unterstützt: PowerShell 7 lässt sich dort nicht installieren. Version 1.x behauptete eine Unterstützung, die sie nicht hatte. |

Von CI getestet auf `windows-latest` mit PowerShell 7.x und Pester 5.7.1 sowie lokal auf
Windows 10/11 mit PowerShell 7.6. Andere Kombinationen sollten funktionieren, werden aber nicht
von CI abgedeckt.

## 6. Installation

### Aus einem Release (empfohlen)

Laden Sie das neueste `Import-CaCertificates-<version>.zip` und `SHA256SUMS.txt` von der
[Releases-Seite](https://github.com/paulmann/Import-CaCertificates/releases/latest) herunter,
prüfen Sie das Archiv und entpacken Sie es in ein Werkzeugverzeichnis wie `C:\Tools\Import-CaCertificates`:

```powershell
$expected = (Select-String -Path .\SHA256SUMS.txt -Pattern '\.zip$').Line.Split(' ')[0]
(Get-FileHash -Algorithm SHA256 -LiteralPath .\Import-CaCertificates-2.0.0.zip).Hash -eq $expected
Expand-Archive -LiteralPath .\Import-CaCertificates-2.0.0.zip -DestinationPath C:\Tools\Import-CaCertificates
```

Das Archiv enthält das Modul (`src/Import-CaCertificates`), den CLI-Wrapper, die
Dokumentation und die Lizenz. Der Wrapper findet das Modul relativ zu sich selbst, sodass
das entpackte Verzeichnis als Ganzes verschoben werden kann.

### Aus dem Quellcode

```powershell
git clone https://github.com/paulmann/Import-CaCertificates.git
cd Import-CaCertificates
```

Es gibt noch keinen Installer und kein PSGallery-Paket. Importieren Sie das Modul direkt:

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Command Import-CaCertificate
```

### Überprüfen

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Help Import-CaCertificate -Full
```

## 7. Schnellstart

**Schritt 1 — den erwarteten SHA-256-Fingerabdruck von der veröffentlichten Seite der CA holen.** Wenn die
CA die Zertifikatsdatei veröffentlicht, berechnen Sie den Fingerabdruck selbst und vergleichen Sie ihn mit
dem Wert, den die CA anderswo veröffentlicht:

```powershell
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('C:\certs\ca.pem')
[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($cert.RawData))
```

**Schritt 2 — Probelauf.** `-WhatIf` lädt herunter, parst, validiert und gibt den Plan aus; es
schreibt nicht in den Speicher:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

`96BCEC06…` ist der SHA-256-Fingerabdruck von ISRG Root X1 in der von Let's Encrypt veröffentlichten
Form; er steht hier als funktionierendes Beispiel, nicht als Empfehlung, irgendeiner CA zu vertrauen.

**Schritt 3 — importieren.** Ohne `-Confirm:$false` fragt eine interaktive Sitzung vor jedem
Schreiben in den Speicher nach einer Bestätigung. Automatisierung muss `-Confirm:$false` übergeben:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru
```

**Schritt 4 — den Speicher überprüfen.**

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG Root X1'
```

Starten Sie den Dienst neu, der die unbekannte CA gemeldet hat (zum Beispiel hMailServer), damit er
den Vertrauensspeicher der Maschine erneut liest.

## 8. Anwendungsbeispiele

### Eine Root-CA aus einer lokalen Datei importieren

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -StoreLocation LocalMachine -Confirm:$false
```

### Nur eine Intermediate-CA importieren

Ein nicht selbstsigniertes CA-Zertifikat wird automatisch nach `LocalMachine\CA` geleitet:

```powershell
Import-CaCertificate -Path 'C:\certs\intermediate.pem' -Thumbprint '<sha256>' -Confirm:$false
```

### Ein Bündel importieren, die Root überspringen

Ein Mehrzertifikat-PEM kann eine Root und ein oder mehrere Intermediates enthalten. Legen Sie jedes
Zertifikat fest, das Sie importieren; `-NoRootImport` überspringt die Root:

```powershell
Import-CaCertificate -Path 'C:\certs\chain.pem' `
    -Thumbprint '<sha256-intermediate-1>', '<sha256-intermediate-2>' `
    -NoRootImport -Confirm:$false
```

### Ein Verzeichnis mit Zertifikaten importieren

```powershell
Import-CaCertificate -Path 'C:\certs\corporate-cas' -Thumbprint '<sha256-1>', '<sha256-2>' -WhatIf -Confirm:$false
```

### Automatisierung mit einem JSON-Bericht

```powershell
$report = Import-CaCertificate -Uri 'https://ca.example.com/root.pem' `
    -Thumbprint '0123...' -Confirm:$false -Json
$report | Out-File -LiteralPath 'C:\logs\ca-import.json' -Encoding utf8NoBOM
```

`-Json` gibt einen einzelnen JSON-Umschlag zurück (`Version`, `Timestamp`, `Summary`, `Results`). Mit
`-Json` wird das Informationsprotokoll unterdrückt, sofern `-LogLevel` nicht ausdrücklich übergeben wird,
sodass stdout nur das JSON-Dokument enthält.

### In eine Datei protokollieren

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' `
    -LogFile 'C:\logs\ca-import.log' -LogLevel Verbose -Confirm:$false
```

### Offline-/Air-Gap-Host

1. Laden Sie das Zertifikat auf einer anderen Maschine herunter und prüfen Sie dessen Fingerabdruck.
2. Kopieren Sie die PEM-/DER-Datei (und ihre SHA-256) auf den Zielhost.
3. Führen Sie `Import-CaCertificate -Path ... -Thumbprint ... -Confirm:$false` aus.

### Eine vorhandene Kopie ersetzen

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' -Force -Confirm:$false
```

`-Force` ersetzt ein Zertifikat mit demselben SHA-256-Fingerabdruck; es umgeht die
Fingerabdruckprüfung nicht.

### Einen Import rückgängig machen

```powershell
Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<SHA-1-thumbprint>
```

Jedes Ergebnisobjekt meldet `ThumbprintSha1` (für `certmgr.msc` / `certutil`) und
`ThumbprintSha256` (die Identitätsprüfung).

Weitere Szenarien: [docs/EXAMPLES.md](docs/EXAMPLES.md).

## 9. Parameter

### Modulbefehl `Import-CaCertificate`

| Parameter | Typ | Standard | Beschreibung |
|---|---|---|---|
| `-Uri` | string[] | — | HTTPS-URL(s) von Zertifikatsdateien (PEM, DER, Base64-DER oder ein Mehrzertifikat-PEM-Bündel). Pflicht im Parametersatz `ByUri`. |
| `-Path` | string[] | — | Lokale Zertifikatsdatei(en) oder Verzeichnisse mit `.cer/.crt/.pem/.der/.cert`-Dateien. Pflicht im Parametersatz `ByPath`. |
| `-Thumbprint` | string[] | — | Erwartete SHA-256-Fingerabdrücke, 64 Hex-Zeichen; Leerzeichen, Doppelpunkte und Bindestriche werden ignoriert. Jedes importierte Zertifikat muss einem der Werte entsprechen. |
| `-StoreLocation` | string | `LocalMachine` | `LocalMachine` (erhöhte Rechte erforderlich) oder `CurrentUser`. |
| `-StoreName` | string | auto | `Root`, `CA`, `AuthRoot` oder `TrustedPeople`. Ohne Angabe geht eine selbstsignierte CA nach `Root` und eine nicht selbstsignierte CA nach `CA`. |
| `-NoRootImport` | switch | aus | Root-CA-Zertifikate überspringen statt importieren. |
| `-AllowUnverifiedRoot` | switch | aus | Einen Root-CA-Import ohne `-Thumbprint` erlauben. Ausdrückliche Vertrauensentscheidung; eine Warnung wird protokolliert und der Lauf als unverifiziert gemeldet. |
| `-RequireConfirmation` | switch | aus | Für jedes Zertifikat zusätzlich zu `ShouldProcess` eine interaktive Ja/Nein-Bestätigung anfordern. In nicht interaktiven Sitzungen nicht nutzbar. |
| `-Force` | switch | aus | Ein vorhandenes Zertifikat mit demselben SHA-256-Fingerabdruck ersetzen. |
| `-PassThru` | switch | aus | Ein Ergebnisobjekt pro Zertifikat zurückgeben. |
| `-Json` | switch | aus | Einen einzelnen JSON-Umschlag zurückgeben (`Version`, `Timestamp`, `Summary`, `Results`). |
| `-LogLevel` | string | `Info` | `None`, `Error`, `Warning`, `Info` oder `Verbose`. |
| `-LogFile` | string | — | Protokollzeilen (UTF-8, ohne BOM) an diese Datei anhängen. |
| `-KeepTempFiles` | switch | aus | Heruntergeladene Dateien im temporären Verzeichnis behalten. |
| `-TempPath` | string | `$env:TEMP` | Übergeordnetes Verzeichnis für ein eindeutiges temporäres Download-Verzeichnis, das danach entfernt wird. Vorhandene Dateien werden nie gelöscht. |
| `-SkipChainValidation` | switch | aus | Die Signaturkettenprüfung zwischen den übergebenen Roots und Intermediates überspringen. |
| `-WhatIf` / `-Confirm` | common | — | Standardverhalten von `ShouldProcess`. |

### CLI-Wrapper `Import-CaCertificates.ps1`

Der Wrapper akzeptiert dieselben Parameter plus zwei veraltete Kompatibilitätsschalter, die
auf `-Uri` abgebildet werden:

| Parameter | Status | Beschreibung |
|---|---|---|
| `-RootUrl` | veraltet | HTTPS-URL eines Root-CA-Zertifikats. Verwenden Sie `-Uri`. |
| `-IntermediateUrl` | veraltet | HTTPS-URL eines Intermediate-CA-Zertifikats. Verwenden Sie `-Uri`. |
| `-KeepFiles` | Alias | Alias von `-KeepTempFiles` (die 1.x-README verwendete diesen Namen). |

Der Wrapper muss aus einem entpackten Release-Verzeichnis (oder dem Repository-Stamm) gestartet werden;
er lädt `src/Import-CaCertificates/Import-CaCertificates.psd1` relativ zu seinem eigenen Speicherort.

## 10. Importergebnisse und Exit-Codes

Jedes Zertifikat erzeugt einen der folgenden Status:

| Status | Bedeutung |
|---|---|
| `Imported` | Zertifikat in den Zielspeicher geschrieben und durch Zurücklesen verifiziert. |
| `Replaced` | Ein vorhandenes Zertifikat mit demselben SHA-256-Fingerabdruck wurde ersetzt (`-Force`). |
| `AlreadyPresent` | Dasselbe Zertifikat ist bereits im Speicher; es wurde nichts geschrieben. |
| `Skipped` | Das Zertifikat wurde durch die Richtlinie ausgeschlossen (`-NoRootImport`). |
| `WhatIf` | Probelauf: Das Zertifikat hat alle Prüfungen bestanden, wurde aber nicht geschrieben. |
| `Declined` | Die interaktive Bestätigung wurde mit „nein“ beantwortet. |

CLI-Exit-Codes:

| Code | Bedeutung |
|---|---|
| `0` | Der Lauf ist beendet (einschließlich Probeläufen, übersprungener Duplikate und abgelehnter Bestätigungen). Überprüfen Sie den Speicher, bevor Sie dies als „importiert“ werten. |
| `1` | Betrieblicher Fehler: Download, Dateisystem, Speicherzugriff, Modul nicht gefunden. |
| `2` | Sicherheits- oder Validierungsverweigerung: reines HTTP, fehlender oder fehlgeschlagener Fingerabdruck, keine CA, abgelaufen, privater Schlüssel, PFX, Kettenfehler, keine erhöhten Rechte für `LocalMachine`. |

## 11. Migration von 1.x

| 1.x | 2.0.0 |
|---|---|
| `-RootUrl` und `-IntermediateUrl` | `-Uri` (eine Liste); die veralteten Namen funktionieren im CLI-Wrapper weiterhin und protokollieren eine Warnung. |
| Keine Fingerabdruckprüfung | `-Thumbprint` ist für jedes Zertifikat Pflicht; Root-CA-Importe werden ohne ihn verweigert, sofern nicht `-AllowUnverifiedRoot` verwendet wird. |
| `-KeepFiles` (dokumentiert) / `-KeepTempFiles` (implementiert) | `-KeepTempFiles`; `-KeepFiles` ist ein Alias. |
| `-TempPath` wurde nach dem Lauf entfernt | Unter `-TempPath` wird ein eindeutiges Unterverzeichnis erstellt und entfernt; vorhandene Dateien werden nicht angetastet. |
| Ein Zertifikat pro URL | Mehrzertifikat-PEM-Bündel, Verzeichnisse und `-Path` werden unterstützt. |
| Root/Intermediate per Parameter gewählt | Wird nach Zertifikatstyp gewählt oder mit `-StoreName` erzwungen. |
| Behauptung Windows 7 / Server 2012 R2 | Windows 10 1607+/11, Windows Server 2012 R2+ mit PowerShell 7.4+. Windows 7 wird nicht unterstützt. |
| Nur Konsolenprotokoll | `-PassThru`, `-Json`, `-LogFile`, `-LogLevel` und Exit-Codes. |

## 12. Fehlerbehebung

| Symptom | Ursache | Maßnahme |
|---|---|---|
| `Root CA import ... requires an expected SHA-256 fingerprint` | Root-CA ohne `-Thumbprint` importiert | Holen Sie den Fingerabdruck von der veröffentlichten Seite der CA und übergeben Sie ihn. |
| `Invalid -Thumbprint value ... SHA-1 thumbprint` | Der Wert ist ein 40-Hex-SHA-1-Thumbprint | Berechnen Sie den SHA-256-Fingerabdruck (64 Hex-Zeichen). |
| `does not match any expected -Thumbprint value` | Falsches Zertifikat oder falscher Fingerabdruck | Vergleichen Sie Subject, Issuer und die ausgegebene SHA-256 mit der Quelle. |
| `Only https:// URLs are allowed` | `http://`-URL | Verwenden Sie die HTTPS-URL der CA; umgehen Sie die Prüfung nicht. |
| `contains a private key` / `PFX/P12` | Die Datei enthält privates Schlüsselmaterial | Exportieren Sie das öffentliche Zertifikat (`Export-Certificate -Type CERT`) und importieren Sie dieses. |
| `failed validation: the certificate is expired` | Abgelaufenes Zertifikat | Besorgen Sie das aktuelle Zertifikat bei der CA. |
| `does not chain to the supplied root certificate(s)` | Root und Intermediate gehören nicht zusammen | Laden Sie das passende Paar herunter oder importieren Sie nur das benötigte Zertifikat. |
| `LocalMachine certificate stores require an elevated session` | Läuft nicht als Administrator | Starten Sie eine erhöhte `pwsh` oder verwenden Sie `-StoreLocation CurrentUser`. |
| `NonInteractive mode` error | Standard-Bestätigungsabfrage in der Automatisierung | Übergeben Sie `-Confirm:$false` (und `-WhatIf` für Probeläufe). |
| `Unknown CA` remains after import | Der abhängige Dienst hat seine Kette zwischengespeichert | Starten Sie den Dienst neu. |

## 13. Entwicklung

```powershell
# Tests (Pester 5.7.1 and 6.x are both supported)
Install-Module Pester -RequiredVersion 5.7.1 -Force -Scope CurrentUser
Invoke-Pester -Path .\tests -Output Detailed

# Static analysis (runs in CI as well)
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1

# Build a release archive and checksums
.\tools\New-Release.ps1 -Version v2.0.0 -OutputDirectory .\out
```

Integrationstests sind gegated: Netzwerktests laufen, wenn `$env:CI` gesetzt ist, und LocalMachine-Tests
laufen nur auf einem CI-Runner mit erhöhten Rechten. Siehe
[tests/Import-CaCertificates.Integration.Tests.ps1](tests/Import-CaCertificates.Integration.Tests.ps1).

CI führt PSScriptAnalyzer und Pester bei jedem Push und Pull Request aus; das Pushen eines `v*`-Tags
baut das Archiv, verifiziert dessen SHA-256 und veröffentlicht das GitHub-Release.

## 14. Lizenz und Support

### Lizenz

Dieses Projekt steht unter der **PolyForm Noncommercial License 1.0.0** — siehe
[LICENSE](LICENSE). Die kommerzielle Nutzung erfordert eine separate Lizenz; wenden Sie sich an den Autor.
Wenn Ihr Anwendungsfall kommerziell ist oder Sie eine permissive Lizenz benötigen, eröffnen Sie ein Issue,
um die Lizenzierung zu besprechen, bevor Sie das Werkzeug einsetzen.

### Autor

Mikhail Deynekin — [GitHub: paulmann](https://github.com/paulmann) —
m@deynekin.com

### Sicherheitsmeldungen

Bitte eröffnen Sie für Sicherheitsprobleme keine öffentlichen Issues. Siehe [SECURITY.md](SECURITY.md).

### Projekt unterstützen

Wenn dieses Werkzeug ein Zertifikatsproblem für Sie gelöst hat, zitieren Sie es mit der
Version und dem Link in Ihrem Runbook. Erstellen Sie nicht automatisch Sterne, Forks oder Kommentare.
