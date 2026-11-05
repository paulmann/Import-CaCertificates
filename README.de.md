# Import-CaCertificates

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates/releases/latest)
[![PowerShell](https://img.shields.io/badge/powershell-7.4%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-lightgrey.svg)](LICENSE)

<!-- md-i18n:switcher -->
**Read this in:** [English](README.md) · **Deutsch** · [中文](README.zh.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · [Русский](README.ru.md)

- [1. Überblick](#1-überblick)
- [2. Was ist neu in 2.0.0](#2-was-ist-neu-in-200)
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
Windows-Zertifikatspeicher. Das Werkzeug ist für Server hinter strengen Firewalls und für
Umgebungen gedacht, die einer bestimmten CA-Kette vertrauen müssen — zum Beispiel
hMailServer, Exim unter Windows, IIS oder eine interne Unternehmens-PKI.

Der Umfang ist bewusst eng: Das Werkzeug lädt öffentliche Zertifikate herunter oder liest
sie aus Dateien, prüft, dass es die erwarteten Zertifikate sind, und importiert sie in die
Speicher `LocalMachine` oder `CurrentUser`. Es fordert, erneuert, sichert, listet oder
löscht keine Zertifikate und importiert niemals private Schlüssel.

Der Import eines Root-CA ist eine Vertrauensentscheidung für den gesamten Rechner. Version
2.0.0 verlangt daher für jedes importierte Zertifikat einen erwarteten SHA-256-Fingerabdruck
und verweigert den Import eines Root-CA ohne diesen, sofern nicht ausdrücklich
`-AllowUnverifiedRoot` angegeben wird.

## 2. Was ist neu in 2.0.0

Version 2.0.0 ist eine sicherheitsorientierte Neufassung. Das Verhalten der Befehle hat sich
bewusst geändert; lesen Sie vor dem Upgrade [CHANGELOG.md](CHANGELOG.md) und
[Migration von 1.x](#11-migration-von-1x).

- Aus einem einzelnen Skript wurde ein Modul (`Import-CaCertificate`) plus ein schlanker
  CLI-Wrapper.
- Root-CA-Importe erfordern einen festgelegten SHA-256-Fingerabdruck; der alte Ablauf nur
  mit `-RootUrl` wird abgelehnt, statt stillschweigend vertraut.
- Reine HTTP-URLs, PFX/P12-Dateien und Dateien mit privaten Schlüsseln werden abgelehnt.
- Zertifikate werden validiert (Gültigkeitszeitraum, CA-Rolle, Key Usage, Signaturalgorithmus),
  und ein Root/Intermediate-Paar wird vor dem Import auf die Kette geprüft.
- Mehrfachzertifikat-PEM-Bündel, lokale Dateien und Verzeichnisse werden unterstützt.
- Die Deduplizierung erfolgt über den SHA-256-Fingerabdruck (der SHA-1-Fingerabdruck wird
  gemeldet, ist aber nicht die Identitätsprüfung).
- Strukturierte Ergebnisse (`-PassThru`), JSON-Berichte (`-Json`), Protokolldateien
  (`-LogFile`), Exit-Codes sowie Pester/PSScriptAnalyzer-CI wurden ergänzt.

## 3. Funktionen

- **Explizite Vertrauensanker**: Jedes importierte Zertifikat muss mit einem über
  `-Thumbprint` übergebenen SHA-256-Fingerabdruck übereinstimmen.
- **Sichere Standardwerte für Root-CAs**: Ein Root-CA-Import ohne Fingerabdruck wird
  abgelehnt; `-AllowUnverifiedRoot` ist die ausdrückliche, deutlich gemeldete Ausnahme.
- **Nur HTTPS**: `http://`-URLs werden vor jeder Anfrage abgelehnt.
- **Nur öffentliche Zertifikate**: PFX/P12-Dateien und jede Datei mit einem privaten
  Schlüssel werden abgelehnt.
- **Validierung**: X.509-Parsing, `NotBefore`/`NotAfter`, Basic Constraints `CA=true`,
  Key Usage `keyCertSign`, fehlerhafte Signaturalgorithmen (MD2/MD5) und schwache
  Schlüssellängen.
- **Kettenprüfung**: Wenn ein Root und ein Intermediate im selben Satz ankommen, muss das
  Intermediate zum übergebenen Root führen (`-SkipChainValidation` deaktiviert die Prüfung).
- **Flexible Eingabe**: HTTPS-URL, lokale PEM/DER-Datei, Base64-DER,
  Mehrfachzertifikat-PEM-Bündel oder ein Verzeichnis mit Zertifikatsdateien.
- **Idempotente Speicherzugriffe**: Ein Zertifikat mit demselben SHA-256-Fingerabdruck wird
  übersprungen; `-Force` ersetzt eine vorhandene Kopie, überspringt aber nie die Prüfung.
- **Automatisierungsfreundlich**: `-WhatIf`, `-Confirm`, `-PassThru`, `-Json`, `-LogFile`,
  `-LogLevel` und unterscheidbare Exit-Codes.
- **Windows-Speicher**: `LocalMachine` (Standard, erhöhte Rechte) und `CurrentUser`, sowie
  die Speicher `Root`, `CA`, `AuthRoot` und `TrustedPeople`.

## 4. Sicherheitsmodell

Das vollständige Bedrohungsmodell steht in [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md).
Die Kurzfassung:

1. Für Downloads wird **ausschließlich HTTPS** akzeptiert.
2. **Der erwartete SHA-256-Fingerabdruck ist Pflicht** für jedes importierte Zertifikat. Für
   ein Root-CA ist er Pflicht, sofern nicht ausdrücklich `-AllowUnverifiedRoot` übergeben wird.
3. **Das Zertifikat wird vor jedem Speicherzugriff geprüft**: als X.509 geparst, innerhalb
   seiner Gültigkeit, als CA gekennzeichnet, zur Zertifikatssignatur berechtigt und mit einem
   akzeptablen Algorithmus signiert.
4. **Das Zertifikat enthält keinen privaten Schlüssel**: Dateien mit privaten Schlüsseln und
   PFX/P12-Container werden abgelehnt.
5. **Bestätigung ist der Standard**: `ConfirmImpact = High` bedeutet, dass ein interaktiver
   Lauf vor dem Schreiben nachfragt; nicht-interaktive Automatisierung muss
   `-Confirm:$false` übergeben.
6. **Keine Telemetrie, keine versteckten Netzwerkzugriffe**: Die einzigen Netzwerkanfragen
   sind die in `-Uri` angegebenen.

Ein festgelegter Fingerabdruck schützt vor einem ausgetauschten Download, einem
kompromittierten Mirror oder einer falschen Datei. Er schützt nicht vor einer CA, die
legitim ein anderes Root-Zertifikat neu ausgestellt hat — deshalb muss der Fingerabdruck von
der veröffentlichten Seite der CA oder aus Ihrer PKI-Dokumentation stammen, nicht von
derselben URL, von der Sie die Datei herunterladen.

## 5. Anforderungen

| Anforderung | Details |
|---|---|
| Betriebssystem | Windows 10 (1607 oder neuer), Windows 11, Windows Server 2012 R2 oder neuer |
| PowerShell | 7.4 oder neuer (`pwsh`). Windows PowerShell 5.1 wird nicht unterstützt. |
| Berechtigungen | Lokaler Administrator für `-StoreLocation LocalMachine`; keine Erhöhung für `-StoreLocation CurrentUser` |
| Netzwerk | HTTPS-Zugriff auf jeden Host in `-Uri`; mit `-Path` nicht erforderlich |
| Windows 7 / 8.1 | Nicht unterstützt: PowerShell 7 lässt sich dort nicht installieren. Version 1.x behauptete eine nicht vorhandene Unterstützung. |

Geprüft in CI unter `windows-latest` mit PowerShell 7.x und Pester 5.7.1 sowie lokal unter
Windows 10/11 mit PowerShell 7.6. Andere Kombinationen sollten funktionieren, sind aber nicht
durch CI abgedeckt.

## 6. Installation

### Aus einem Release (empfohlen)

Laden Sie das neueste `Import-CaCertificates-<version>.zip` und `SHA256SUMS.txt` von der
[Releases-Seite](https://github.com/paulmann/Import-CaCertificates/releases/latest) herunter,
prüfen Sie das Archiv und entpacken Sie es in ein Werkzeugverzeichnis wie
`C:\Tools\Import-CaCertificates`:

```powershell
$expected = (Select-String -Path .\SHA256SUMS.txt -Pattern '\.zip$').Line.Split(' ')[0]
(Get-FileHash -Algorithm SHA256 -LiteralPath .\Import-CaCertificates-2.0.0.zip).Hash -eq $expected
Expand-Archive -LiteralPath .\Import-CaCertificates-2.0.0.zip -DestinationPath C:\Tools\Import-CaCertificates
```

Das Archiv enthält das Modul (`src/Import-CaCertificates`), den CLI-Wrapper, die
Dokumentation und die Lizenz. Der Wrapper findet das Modul relativ zu seinem eigenen
Speicherort, daher kann das entpackte Verzeichnis als Ganzes verschoben werden.

### Aus dem Quellcode

```powershell
git clone https://github.com/paulmann/Import-CaCertificates.git
cd Import-CaCertificates
```

Es gibt noch kein Installationsprogramm und kein PSGallery-Paket. Importieren Sie das Modul
direkt:

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Command Import-CaCertificate
```

### Prüfen

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Help Import-CaCertificate -Full
```

## 7. Schnellstart

**Schritt 1 — holen Sie den erwarteten SHA-256-Fingerabdruck von der veröffentlichten Seite
der CA.** Wenn die CA die Zertifikatsdatei veröffentlicht, berechnen Sie den Fingerabdruck
selbst und vergleichen Sie ihn mit dem Wert, den die CA an anderer Stelle veröffentlicht:

```powershell
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('C:\certs\ca.pem')
[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($cert.RawData))
```

**Schritt 2 — Probelauf.** `-WhatIf` lädt herunter, parst, validiert und zeigt den Plan; in
den Speicher wird nichts geschrieben:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

`96BCEC06…` ist der von Let's Encrypt veröffentlichte SHA-256-Fingerabdruck von ISRG Root
X1; er dient als funktionierendes Beispiel, nicht als Empfehlung, einer bestimmten CA zu
vertrauen.

**Schritt 3 — Importieren.** Ohne `-Confirm:$false` fragt eine interaktive Sitzung vor jedem
Schreibvorgang nach einer Bestätigung. Automatisierung muss `-Confirm:$false` übergeben:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru
```

**Schritt 4 — Speicher prüfen.**

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG Root X1'
```

Starten Sie den Dienst neu, der den unbekannten CA gemeldet hat (zum Beispiel hMailServer),
damit er den Vertrauensspeicher des Rechners neu einliest.

## 8. Anwendungsbeispiele

### Root-CA aus einer lokalen Datei importieren

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -StoreLocation LocalMachine -Confirm:$false
```

### Nur ein Intermediate-CA importieren

Ein nicht selbstsigniertes CA-Zertifikat wird automatisch nach `LocalMachine\CA` geleitet:

```powershell
Import-CaCertificate -Path 'C:\certs\intermediate.pem' -Thumbprint '<sha256>' -Confirm:$false
```

### Ein Bündel importieren und den Root überspringen

Ein Mehrfachzertifikat-PEM kann einen Root und ein oder mehrere Intermediates enthalten.
Legen Sie jedes importierte Zertifikat fest; `-NoRootImport` überspringt den Root:

```powershell
Import-CaCertificate -Path 'C:\certs\chain.pem' `
    -Thumbprint '<sha256-intermediate-1>', '<sha256-intermediate-2>' `
    -NoRootImport -Confirm:$false
```

### Ein Verzeichnis mit Zertifikaten importieren

```powershell
Import-CaCertificate -Path 'C:\certs\corporate-cas' -Thumbprint '<sha256-1>', '<sha256-2>' -WhatIf -Confirm:$false
```

### Automatisierung mit JSON-Bericht

```powershell
$report = Import-CaCertificate -Uri 'https://ca.example.com/root.pem' `
    -Thumbprint '0123...' -Confirm:$false -Json
$report | Out-File -LiteralPath 'C:\logs\ca-import.json' -Encoding utf8NoBOM
```

`-Json` liefert einen JSON-Umschlag (`Version`, `Timestamp`, `Summary`, `Results`). Mit
`-Json` wird das Informationsprotokoll unterdrückt, sofern `-LogLevel` nicht ausdrücklich
übergeben wird; stdout enthält dann nur das JSON-Dokument.

### In eine Datei protokollieren

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' `
    -LogFile 'C:\logs\ca-import.log' -LogLevel Verbose -Confirm:$false
```

### Offline-/Air-Gap-Host

1. Laden Sie das Zertifikat auf einem anderen Rechner herunter und prüfen Sie den
   Fingerabdruck.
2. Kopieren Sie die PEM/DER-Datei (und ihren SHA-256) auf den Zielhost.
3. Führen Sie `Import-CaCertificate -Path ... -Thumbprint ... -Confirm:$false` aus.

### Eine vorhandene Kopie ersetzen

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' -Force -Confirm:$false
```

`-Force` ersetzt ein Zertifikat mit demselben SHA-256-Fingerabdruck; die Fingerabdruckprüfung
wird dadurch nicht umgangen.

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
| `-Uri` | string[] | — | HTTPS-URL(s) von Zertifikatsdateien (PEM, DER, Base64-DER oder ein Mehrfachzertifikat-PEM-Bündel). Pflicht im Parametersatz `ByUri`. |
| `-Path` | string[] | — | Lokale Zertifikatsdatei(en) oder Verzeichnisse mit `.cer/.crt/.pem/.der/.cert`-Dateien. Pflicht im Parametersatz `ByPath`. |
| `-Thumbprint` | string[] | — | Erwartete SHA-256-Fingerabdrücke, 64 Hex-Zeichen; Leerzeichen, Doppelpunkte und Bindestriche werden ignoriert. Jedes importierte Zertifikat muss mit einem der Werte übereinstimmen. |
| `-StoreLocation` | string | `LocalMachine` | `LocalMachine` (erhöhte Rechte erforderlich) oder `CurrentUser`. |
| `-StoreName` | string | auto | `Root`, `CA`, `AuthRoot` oder `TrustedPeople`. Ohne Angabe geht ein selbstsigniertes CA in `Root` und ein nicht selbstsigniertes in `CA`. |
| `-NoRootImport` | switch | aus | Root-CA-Zertifikate statt Import überspringen. |
| `-AllowUnverifiedRoot` | switch | aus | Root-CA-Import ohne `-Thumbprint` erlauben. Ausdrückliche Vertrauensentscheidung; es wird gewarnt und der Lauf als ungeprüft gemeldet. |
| `-RequireConfirmation` | switch | aus | Zusätzlich zu `ShouldProcess` für jedes Zertifikat eine interaktive Ja/Nein-Bestätigung anfordern. In nicht-interaktiven Sitzungen nicht verwendbar. |
| `-Force` | switch | aus | Ein vorhandenes Zertifikat mit demselben SHA-256-Fingerabdruck ersetzen. |
| `-PassThru` | switch | aus | Je Zertifikat ein Ergebnisobjekt zurückgeben. |
| `-Json` | switch | aus | Einen JSON-Umschlag (`Version`, `Timestamp`, `Summary`, `Results`) zurückgeben. |
| `-LogLevel` | string | `Info` | `None`, `Error`, `Warning`, `Info` oder `Verbose`. |
| `-LogFile` | string | — | Protokollzeilen (UTF-8 ohne BOM) an diese Datei anhängen. |
| `-KeepTempFiles` | switch | aus | Heruntergeladene Dateien im temporären Verzeichnis behalten. |
| `-TempPath` | string | `$env:TEMP` | Übergeordnetes Verzeichnis für ein eindeutiges temporäres Download-Verzeichnis, das danach entfernt wird. Vorhandene Dateien werden nie gelöscht. |
| `-SkipChainValidation` | switch | aus | Die Signaturkettenprüfung zwischen übergebenen Roots und Intermediates überspringen. |
| `-WhatIf` / `-Confirm` | allgemein | — | Standardverhalten von `ShouldProcess`. |

### CLI-Wrapper `Import-CaCertificates.ps1`

Der Wrapper akzeptiert dieselben Parameter plus zwei veraltete Kompatibilitätsschalter, die
auf `-Uri` abgebildet werden:

| Parameter | Status | Beschreibung |
|---|---|---|
| `-RootUrl` | veraltet | HTTPS-URL eines Root-CA. Verwenden Sie `-Uri`. |
| `-IntermediateUrl` | veraltet | HTTPS-URL eines Intermediate-CA. Verwenden Sie `-Uri`. |
| `-KeepFiles` | Alias | Alias von `-KeepTempFiles` (dieser Name wurde im README 1.x verwendet). |

Der Wrapper muss aus einem entpackten Release (oder dem Repository-Stamm) gestartet werden;
er lädt `src/Import-CaCertificates/Import-CaCertificates.psd1` relativ zu seinem eigenen
Speicherort.

## 10. Importergebnisse und Exit-Codes

Jedes Zertifikat erhält einen der folgenden Status:

| Status | Bedeutung |
|---|---|
| `Imported` | Zertifikat in den Zielspeicher geschrieben und durch Zurücklesen verifiziert. |
| `Replaced` | Ein vorhandenes Zertifikat mit demselben SHA-256-Fingerabdruck wurde ersetzt (`-Force`). |
| `AlreadyPresent` | Dasselbe Zertifikat ist bereits im Speicher; es wurde nichts geschrieben. |
| `Skipped` | Das Zertifikat wurde durch die Richtlinie ausgeschlossen (`-NoRootImport`). |
| `WhatIf` | Probelauf: Das Zertifikat hat alle Prüfungen bestanden, wurde aber nicht geschrieben. |
| `Declined` | Die interaktive Bestätigung wurde mit „Nein“ beantwortet. |

CLI-Exit-Codes:

| Code | Bedeutung |
|---|---|
| `0` | Der Lauf ist beendet (auch Probeläufe, übersprungene Duplikate und abgelehnte Bestätigungen). Prüfen Sie den Speicher, bevor Sie dies als „importiert“ werten. |
| `1` | Betriebsfehler: Download, Dateisystem, Speicherzugriff, Modul nicht gefunden. |
| `2` | Sicherheits- oder Validierungsverweigerung: reines HTTP, fehlender/nicht passender Fingerabdruck, kein CA, abgelaufen, privater Schlüssel, PFX, Kettenfehler, keine erhöhten Rechte für `LocalMachine`. |

## 11. Migration von 1.x

| 1.x | 2.0.0 |
|---|---|
| `-RootUrl` und `-IntermediateUrl` | `-Uri` (eine Liste); die veralteten Namen funktionieren im CLI-Wrapper weiterhin und protokollieren eine Warnung. |
| Keine Fingerabdruckprüfung | `-Thumbprint` ist für jedes Zertifikat Pflicht; Root-CA-Importe werden ohne ihn abgelehnt, sofern `-AllowUnverifiedRoot` verwendet wird. |
| `-KeepFiles` (dokumentiert) / `-KeepTempFiles` (implementiert) | `-KeepTempFiles`; `-KeepFiles` ist ein Alias. |
| `-TempPath` wurde nach dem Lauf entfernt | Unter `-TempPath` wird ein eindeutiges Unterverzeichnis erstellt und entfernt; vorhandene Dateien bleiben unberührt. |
| Ein Zertifikat pro URL | Mehrfachzertifikat-PEM-Bündel, Verzeichnisse und `-Path` werden unterstützt. |
| Root/Intermediate per Parameter gewählt | Auswahl nach Zertifikatstyp oder erzwungen über `-StoreName`. |
| Aussage zu Windows 7 / Server 2012 R2 | Windows 10 1607+/11, Windows Server 2012 R2+ mit PowerShell 7.4+. Windows 7 wird nicht unterstützt. |
| Nur Konsolenprotokoll | `-PassThru`, `-Json`, `-LogFile`, `-LogLevel` und Exit-Codes. |

## 12. Fehlerbehebung

| Symptom | Ursache | Maßnahme |
|---|---|---|
| `Root CA import ... requires an expected SHA-256 fingerprint` | Root-CA ohne `-Thumbprint` importiert | Holen Sie den Fingerabdruck von der veröffentlichten CA-Seite und übergeben Sie ihn. |
| `Invalid -Thumbprint value ... SHA-1 thumbprint` | Der Wert ist ein 40-stelliger SHA-1-Fingerabdruck | Berechnen Sie den SHA-256-Fingerabdruck (64 Hex-Zeichen). |
| `does not match any expected -Thumbprint value` | Falsches Zertifikat oder falscher Fingerabdruck | Vergleichen Sie Subject, Issuer und den ausgegebenen SHA-256 mit der Quelle. |
| `Only https:// URLs are allowed` | `http://`-URL | Verwenden Sie die HTTPS-URL der CA; umgehen Sie die Prüfung nicht. |
| `contains a private key` / `PFX/P12` | Die Datei enthält privates Schlüsselmaterial | Exportieren Sie das öffentliche Zertifikat (`Export-Certificate -Type CERT`) und importieren Sie dieses. |
| `failed validation: the certificate is expired` | Zertifikat abgelaufen | Besorgen Sie das aktuelle Zertifikat bei der CA. |
| `does not chain to the supplied root certificate(s)` | Root und Intermediate gehören nicht zusammen | Laden Sie das passende Paar herunter oder importieren Sie nur das benötigte Zertifikat. |
| `LocalMachine certificate stores require an elevated session` | Lauf ohne Administratorrechte | Starten Sie `pwsh` mit erhöhten Rechten oder verwenden Sie `-StoreLocation CurrentUser`. |
| Fehler `NonInteractive mode` | Standard-Bestätigungsabfrage in der Automatisierung | Übergeben Sie `-Confirm:$false` (und `-WhatIf` für Probeläufe). |
| `Unknown CA` bleibt nach dem Import | Der Dienst hat seine Kette zwischengespeichert | Starten Sie den Dienst neu. |

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

Integrationstests sind eingeschränkt: Netzwerktests laufen, wenn `$env:CI` gesetzt ist, und
LocalMachine-Tests nur auf einem erhöhten CI-Runner. Siehe
[tests/Import-CaCertificates.Integration.Tests.ps1](tests/Import-CaCertificates.Integration.Tests.ps1).

CI führt PSScriptAnalyzer und Pester bei jedem Push und Pull Request aus; ein Push eines
`v*`-Tags baut das Archiv, prüft dessen SHA-256 und veröffentlicht das GitHub-Release.

## 14. Lizenz und Support

### Lizenz

Dieses Projekt steht unter der **PolyForm Noncommercial License 1.0.0** — siehe
[LICENSE](LICENSE). Kommerzielle Nutzung erfordert eine separate Lizenz; wenden Sie sich an
den Autor. Wenn Sie eine kommerzielle oder permissive Lizenz benötigen, öffnen Sie ein
Issue, um die Lizenzierung vor der Einführung zu klären.

### Autor

Mikhail Deynekin — [GitHub: paulmann](https://github.com/paulmann) —
m@deynekin.com

### Sicherheitsmeldungen

Bitte öffnen Sie für Sicherheitsprobleme keine öffentlichen Issues. Siehe
[SECURITY.md](SECURITY.md).

### Projekt unterstützen

Wenn dieses Werkzeug ein Zertifikatsproblem für Sie gelöst hat, nennen Sie es in Ihrem
Runbook mit Version und Link. Erstellen Sie keine Sterne, Forks oder Kommentare automatisch.
