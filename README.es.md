# Import-CaCertificates

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates/releases/latest)
[![PowerShell](https://img.shields.io/badge/powershell-7.4%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-lightgrey.svg)](LICENSE)

<!-- md-i18n:switcher -->
**Read this in:** [English](README.md) · [Deutsch](README.de.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md) · **Español** · [Русский](README.ru.md)

- [1. Descripción general](#1-descripción-general)
- [2. Qué cambia en 2.0.0](#2-qué-cambia-en-200)
- [3. Características](#3-características)
- [4. Modelo de seguridad](#4-modelo-de-seguridad)
- [5. Requisitos](#5-requisitos)
- [6. Instalación](#6-instalación)
- [7. Inicio rápido](#7-inicio-rápido)
- [8. Ejemplos de uso](#8-ejemplos-de-uso)
- [9. Parámetros](#9-parámetros)
- [10. Resultados de importación y códigos de salida](#10-resultados-de-importación-y-códigos-de-salida)
- [11. Migración desde 1.x](#11-migración-desde-1x)
- [12. Solución de problemas](#12-solución-de-problemas)
- [13. Desarrollo](#13-desarrollo)
- [14. Licencia y soporte](#14-licencia-y-soporte)

***

## 1. Descripción general

**Import-CaCertificates** importa certificados públicos de CA (raíz e intermedios) en los
almacenes de certificados de Windows. La herramienta está pensada para servidores detrás de
firewalls restrictivos y para implementaciones que deben confiar en una cadena de CA
concreta — por ejemplo hMailServer, Exim en Windows, IIS o una PKI corporativa interna.

El alcance es deliberadamente limitado: descarga o lee certificados públicos, comprueba que
sean los certificados esperados y los importa en los almacenes `LocalMachine` o
`CurrentUser`. No solicita, renueva, respalda, enumera ni elimina certificados, y nunca
importa claves privadas.

Importar una CA raíz es una decisión de confianza para toda la máquina. Por eso la versión
2.0.0 exige una huella SHA-256 esperada para cada certificado importado y rechaza la
importación de una CA raíz sin ella, salvo que se use explícitamente
`-AllowUnverifiedRoot`.

## 2. Qué cambia en 2.0.0

La versión 2.0.0 es una reescritura centrada en la seguridad. El comportamiento del comando
cambió de forma intencionada; consulte [CHANGELOG.md](CHANGELOG.md) y
[Migración desde 1.x](#11-migración-desde-1x) antes de actualizar.

- El único script se convirtió en un módulo (`Import-CaCertificate`) más un envoltorio CLI
  fino.
- La importación de CA raíz exige una huella SHA-256 fijada; el flujo antiguo solo con
  `-RootUrl` se rechaza en lugar de confiar en él silenciosamente.
- Se rechazan las URL HTTP sin cifrar, los archivos PFX/P12 y los archivos con claves
  privadas.
- Los certificados se validan (periodo de validez, rol de CA, Key Usage, algoritmo de
  firma), y un par raíz/intermedio se comprueba contra la cadena antes de importar.
- Se admiten paquetes PEM con varios certificados, archivos locales y directorios.
- La deduplicación usa la huella SHA-256 (la huella SHA-1 se informa, pero no es la
  comprobación de identidad).
- Se añadieron resultados estructurados (`-PassThru`), informes JSON (`-Json`), archivos de
  registro (`-LogFile`), códigos de salida y CI con Pester/PSScriptAnalyzer.

## 3. Características

- **Anclaje de confianza explícito**: cada certificado importado debe coincidir con una
  huella SHA-256 esperada pasada en `-Thumbprint`.
- **Valores seguros por defecto para CA raíz**: se rechaza la importación de una CA raíz sin
  huella; `-AllowUnverifiedRoot` es la excepción explícita y ruidosamente informada.
- **Solo HTTPS**: las URL `http://` se rechazan antes de cualquier petición.
- **Solo certificados públicos**: los archivos PFX/P12 y cualquier archivo con una clave
  privada se rechazan.
- **Validación**: análisis X.509, `NotBefore`/`NotAfter`, Basic Constraints `CA=true`,
  Key Usage `keyCertSign`, algoritmos de firma rotos (MD2/MD5) y tamaños de clave débiles.
- **Validación de cadena**: cuando una raíz y un intermedio llegan en el mismo lote, el
  intermedio debe encadenar con la raíz suministrada (`-SkipChainValidation` lo desactiva).
- **Entrada flexible**: URL HTTPS, archivo PEM/DER local, DER en base64, paquete PEM con
  varios certificados o un directorio de archivos de certificados.
- **Escrituras idempotentes**: un certificado con la misma huella SHA-256 se omite; `-Force`
  reemplaza una copia existente pero nunca omite la verificación.
- **Compatible con automatización**: `-WhatIf`, `-Confirm`, `-PassThru`, `-Json`, `-LogFile`,
  `-LogLevel` y códigos de salida diferenciados.
- **Almacenes de Windows**: `LocalMachine` (predeterminado, con privilegios) y
  `CurrentUser`, almacenes `Root`, `CA`, `AuthRoot` y `TrustedPeople`.

## 4. Modelo de seguridad

El modelo de amenazas completo está en [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md).
Resumen:

1. **Solo HTTPS** se acepta para las descargas.
2. **La huella SHA-256 esperada es obligatoria** para cada certificado importado. Para una CA
   raíz es obligatoria salvo que se pase `-AllowUnverifiedRoot` explícitamente.
3. **El certificado se valida antes de cualquier escritura**: se analiza como X.509, está
   dentro de su periodo de validez, está marcado como CA, puede firmar certificados y está
   firmado con un algoritmo aceptable.
4. **El certificado no es una clave privada**: los archivos con claves privadas y los
   contenedores PFX/P12 se rechazan.
5. **La confirmación es lo predeterminado**: `ConfirmImpact = High` significa que una
   ejecución interactiva pregunta antes de escribir; la automatización no interactiva debe
   pasar `-Confirm:$false`.
6. **Sin telemetría ni accesos de red ocultos**: las únicas peticiones de red son los valores
   de `-Uri`.

Una huella fijada protege contra una descarga sustituida, un espejo comprometido o un archivo
equivocado. No protege contra una CA que reemitió legítimamente otra raíz — por eso la huella
debe venir de la página publicada por la CA o de la documentación de su PKI, no de la misma
URL desde la que descarga el archivo.

## 5. Requisitos

| Requisito | Detalles |
|---|---|
| Sistema operativo | Windows 10 (1607 o posterior), Windows 11, Windows Server 2012 R2 o posterior |
| PowerShell | 7.4 o posterior (`pwsh`). Windows PowerShell 5.1 no es compatible. |
| Permisos | Administrador local para `-StoreLocation LocalMachine`; sin elevación para `-StoreLocation CurrentUser` |
| Red | Acceso HTTPS a cada host de `-Uri`; no se necesita con `-Path` |
| Windows 7 / 8.1 | No compatibles: PowerShell 7 no se instala allí. La versión 1.x afirmaba una compatibilidad que no tenía. |

Probado en CI en `windows-latest` con PowerShell 7.x y Pester 5.7.1, y localmente en
Windows 10/11 con PowerShell 7.6. Se espera que otras combinaciones funcionen, pero no están
cubiertas por CI.

## 6. Instalación

### Desde un release (recomendado)

Descargue el `Import-CaCertificates-<version>.zip` más reciente y `SHA256SUMS.txt` de la
[página de releases](https://github.com/paulmann/Import-CaCertificates/releases/latest),
verifique el archivo y extráigalo en un directorio de herramientas como
`C:\Tools\Import-CaCertificates`:

```powershell
$expected = (Select-String -Path .\SHA256SUMS.txt -Pattern '\.zip$').Line.Split(' ')[0]
(Get-FileHash -Algorithm SHA256 -LiteralPath .\Import-CaCertificates-2.0.0.zip).Hash -eq $expected
Expand-Archive -LiteralPath .\Import-CaCertificates-2.0.0.zip -DestinationPath C:\Tools\Import-CaCertificates
```

El archivo contiene el módulo (`src/Import-CaCertificates`), el envoltorio CLI, la
documentación y la licencia. El envoltorio localiza el módulo en relación con su propia
ubicación, por lo que el directorio extraído puede moverse como un todo.

### Desde el código fuente

```powershell
git clone https://github.com/paulmann/Import-CaCertificates.git
cd Import-CaCertificates
```

Todavía no hay instalador ni paquete en PSGallery. Importe el módulo directamente:

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Command Import-CaCertificate
```

### Verificar

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Help Import-CaCertificate -Full
```

## 7. Inicio rápido

**Paso 1 — obtenga la huella SHA-256 esperada de la página publicada por la CA.** Si la CA
publica el archivo del certificado, calcule la huella usted mismo y compárela con el valor que
la CA publica por otro canal:

```powershell
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('C:\certs\ca.pem')
[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($cert.RawData))
```

**Paso 2 — simulación.** `-WhatIf` descarga, analiza, valida e imprime el plan; no escribe en
el almacén:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

`96BCEC06…` es la huella SHA-256 de ISRG Root X1 publicada por Let's Encrypt; se muestra como
ejemplo funcional, no como recomendación de confiar en ninguna CA.

**Paso 3 — importar.** Sin `-Confirm:$false`, una sesión interactiva pide confirmación antes
de cada escritura. La automatización debe pasar `-Confirm:$false`:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru
```

**Paso 4 — verifique el almacén.**

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG Root X1'
```

Reinicie el servicio que informaba de la CA desconocida (por ejemplo hMailServer) para que
vuelva a leer el almacén de confianza de la máquina.

## 8. Ejemplos de uso

### Importar una CA raíz desde un archivo local

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -StoreLocation LocalMachine -Confirm:$false
```

### Importar solo una CA intermedia

Un certificado de CA no autofirmado se dirige automáticamente a `LocalMachine\CA`:

```powershell
Import-CaCertificate -Path 'C:\certs\intermediate.pem' -Thumbprint '<sha256>' -Confirm:$false
```

### Importar un paquete y omitir la raíz

Un PEM con varios certificados puede contener una raíz y uno o más intermedios. Fije cada
certificado que importe; `-NoRootImport` omite la raíz:

```powershell
Import-CaCertificate -Path 'C:\certs\chain.pem' `
    -Thumbprint '<sha256-intermediate-1>', '<sha256-intermediate-2>' `
    -NoRootImport -Confirm:$false
```

### Importar un directorio de certificados

```powershell
Import-CaCertificate -Path 'C:\certs\corporate-cas' -Thumbprint '<sha256-1>', '<sha256-2>' -WhatIf -Confirm:$false
```

### Automatización con un informe JSON

```powershell
$report = Import-CaCertificate -Uri 'https://ca.example.com/root.pem' `
    -Thumbprint '0123...' -Confirm:$false -Json
$report | Out-File -LiteralPath 'C:\logs\ca-import.json' -Encoding utf8NoBOM
```

`-Json` devuelve un único sobre JSON (`Version`, `Timestamp`, `Summary`, `Results`). Con
`-Json` el registro informativo se suprime salvo que se pase `-LogLevel` explícitamente, por
lo que stdout contiene solo el documento JSON.

### Registrar en un archivo

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' `
    -LogFile 'C:\logs\ca-import.log' -LogLevel Verbose -Confirm:$false
```

### Host aislado / air-gapped

1. Descargue el certificado en otra máquina y verifique su huella.
2. Copie el archivo PEM/DER (y su SHA-256) al host de destino.
3. Ejecute `Import-CaCertificate -Path ... -Thumbprint ... -Confirm:$false`.

### Reemplazar una copia existente

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' -Force -Confirm:$false
```

`-Force` reemplaza un certificado con la misma huella SHA-256; no omite la comprobación de la
huella.

### Deshacer una importación

```powershell
Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<SHA-1-thumbprint>
```

Cada objeto de resultado informa de `ThumbprintSha1` (para `certmgr.msc` / `certutil`) y
`ThumbprintSha256` (la comprobación de identidad).

Más escenarios: [docs/EXAMPLES.md](docs/EXAMPLES.md).

## 9. Parámetros

### Comando del módulo `Import-CaCertificate`

| Parámetro | Tipo | Predeterminado | Descripción |
|---|---|---|---|
| `-Uri` | string[] | — | URL HTTPS de archivos de certificado (PEM, DER, DER en base64 o un paquete PEM con varios certificados). Obligatorio en el conjunto `ByUri`. |
| `-Path` | string[] | — | Archivos de certificado locales o directorios con archivos `.cer/.crt/.pem/.der/.cert`. Obligatorio en el conjunto `ByPath`. |
| `-Thumbprint` | string[] | — | Huellas SHA-256 esperadas, 64 caracteres hexadecimales; se ignoran espacios, dos puntos y guiones. Cada certificado importado debe coincidir con uno de los valores. |
| `-StoreLocation` | string | `LocalMachine` | `LocalMachine` (requiere elevación) o `CurrentUser`. |
| `-StoreName` | string | auto | `Root`, `CA`, `AuthRoot` o `TrustedPeople`. Sin él, una CA autofirmada va a `Root` y una CA no autofirmada a `CA`. |
| `-NoRootImport` | switch | desactivado | Omitir los certificados de CA raíz en lugar de importarlos. |
| `-AllowUnverifiedRoot` | switch | desactivado | Permitir la importación de una CA raíz sin `-Thumbprint`. Decisión de confianza explícita; se registra una advertencia y la ejecución se informa como no verificada. |
| `-RequireConfirmation` | switch | desactivado | Pedir una confirmación interactiva sí/no para cada certificado, además de `ShouldProcess`. No usable en sesiones no interactivas. |
| `-Force` | switch | desactivado | Reemplazar un certificado existente con la misma huella SHA-256. |
| `-PassThru` | switch | desactivado | Devolver un objeto de resultado por certificado. |
| `-Json` | switch | desactivado | Devolver un único sobre JSON (`Version`, `Timestamp`, `Summary`, `Results`). |
| `-LogLevel` | string | `Info` | `None`, `Error`, `Warning`, `Info` o `Verbose`. |
| `-LogFile` | string | — | Añadir líneas de registro (UTF-8 sin BOM) a este archivo. |
| `-KeepTempFiles` | switch | desactivado | Conservar los archivos descargados en el directorio temporal. |
| `-TempPath` | string | `$env:TEMP` | Directorio principal para un directorio temporal único de descarga, que se elimina después. Los archivos existentes nunca se eliminan. |
| `-SkipChainValidation` | switch | desactivado | Omitir la comprobación de la cadena de firmas entre las raíces y los intermedios suministrados. |
| `-WhatIf` / `-Confirm` | comunes | — | Comportamiento estándar de `ShouldProcess`. |

### Envoltorio CLI `Import-CaCertificates.ps1`

El envoltorio acepta los mismos parámetros más dos modificadores de compatibilidad obsoletos
asignados a `-Uri`:

| Parámetro | Estado | Descripción |
|---|---|---|
| `-RootUrl` | obsoleto | URL HTTPS de una CA raíz. Use `-Uri`. |
| `-IntermediateUrl` | obsoleto | URL HTTPS de una CA intermedia. Use `-Uri`. |
| `-KeepFiles` | alias | Alias de `-KeepTempFiles` (el README 1.x usaba este nombre). |

El envoltorio debe iniciarse desde un release extraído (o la raíz del repositorio); carga
`src/Import-CaCertificates/Import-CaCertificates.psd1` en relación con su propia ubicación.

## 10. Resultados de importación y códigos de salida

Cada certificado produce uno de los siguientes estados:

| Estado | Significado |
|---|---|
| `Imported` | Certificado escrito en el almacén de destino y verificado leyéndolo de nuevo. |
| `Replaced` | Se reemplazó un certificado existente con la misma huella SHA-256 (`-Force`). |
| `AlreadyPresent` | El mismo certificado ya está en el almacén; no se escribió nada. |
| `Skipped` | El certificado fue excluido por la política (`-NoRootImport`). |
| `WhatIf` | Simulación: el certificado pasó todas las comprobaciones pero no se escribió. |
| `Declined` | La confirmación interactiva se respondió con «no». |

Códigos de salida del CLI:

| Código | Significado |
|---|---|
| `0` | La ejecución terminó (incluidas simulaciones, duplicados omitidos y confirmaciones rechazadas). Verifique el almacén antes de considerarlo «importado». |
| `1` | Fallo operativo: descarga, sistema de archivos, acceso al almacén, módulo no encontrado. |
| `2` | Rechazo de seguridad o validación: HTTP simple, huella ausente o incorrecta, no es CA, expirado, clave privada, PFX, cadena incorrecta, sin elevación para `LocalMachine`. |

## 11. Migración desde 1.x

| 1.x | 2.0.0 |
|---|---|
| `-RootUrl` y `-IntermediateUrl` | `-Uri` (una lista); los nombres obsoletos siguen funcionando en el envoltorio CLI y registran una advertencia. |
| Sin comprobación de huella | `-Thumbprint` es obligatorio para cada certificado; la importación de CA raíz se rechaza sin él salvo que se use `-AllowUnverifiedRoot`. |
| `-KeepFiles` (documentado) / `-KeepTempFiles` (implementado) | `-KeepTempFiles`; `-KeepFiles` es un alias. |
| `-TempPath` se eliminaba tras la ejecución | Se crea un subdirectorio único bajo `-TempPath` y se elimina; los archivos existentes no se tocan. |
| Un certificado por URL | Se admiten paquetes PEM con varios certificados, directorios y `-Path`. |
| Raíz/intermedio elegidos por parámetro | Se eligen por tipo de certificado, o se fuerzan con `-StoreName`. |
| Afirmación sobre Windows 7 / Server 2012 R2 | Windows 10 1607+/11, Windows Server 2012 R2+ con PowerShell 7.4+. Windows 7 no es compatible. |
| Solo registro en consola | `-PassThru`, `-Json`, `-LogFile`, `-LogLevel` y códigos de salida. |

## 12. Solución de problemas

| Síntoma | Causa | Acción |
|---|---|---|
| `Root CA import ... requires an expected SHA-256 fingerprint` | CA raíz importada sin `-Thumbprint` | Obtenga la huella de la página publicada por la CA y pásala. |
| `Invalid -Thumbprint value ... SHA-1 thumbprint` | El valor es una huella SHA-1 de 40 caracteres | Calcule la huella SHA-256 (64 caracteres hexadecimales). |
| `does not match any expected -Thumbprint value` | Certificado o huella incorrectos | Compare el subject, el issuer y el SHA-256 impreso con el origen. |
| `Only https:// URLs are allowed` | URL `http://` | Use la URL HTTPS de la CA; no eluda la comprobación. |
| `contains a private key` / `PFX/P12` | El archivo contiene material de clave privada | Exporte el certificado público (`Export-Certificate -Type CERT`) e impórtelo. |
| `failed validation: the certificate is expired` | Certificado expirado | Obtenga el certificado actual de la CA. |
| `does not chain to the supplied root certificate(s)` | La raíz y el intermedio no pertenecen juntos | Descargue el par correcto o importe solo el certificado que necesita. |
| `LocalMachine certificate stores require an elevated session` | No se ejecuta como administrador | Inicie `pwsh` elevado o use `-StoreLocation CurrentUser`. |
| Error `NonInteractive mode` | Petición de confirmación por defecto en automatización | Pase `-Confirm:$false` (y `-WhatIf` para simulaciones). |
| `Unknown CA` persiste tras la importación | El servicio almacenó su cadena en caché | Reinicie el servicio. |

## 13. Desarrollo

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

Las pruebas de integración están condicionadas: las de red se ejecutan cuando `$env:CI` está
definido, y las de `LocalMachine` solo en un runner de CI elevado. Véase
[tests/Import-CaCertificates.Integration.Tests.ps1](tests/Import-CaCertificates.Integration.Tests.ps1).

CI ejecuta PSScriptAnalyzer y Pester en cada push y pull request; al publicar una etiqueta
`v*` se construye el archivo, se verifica su SHA-256 y se publica el release de GitHub.

## 14. Licencia y soporte

### Licencia

Este proyecto está licenciado bajo la **PolyForm Noncommercial License 1.0.0** — véase
[LICENSE](LICENSE). El uso comercial requiere una licencia separada; contacte con el autor.
Si su caso es comercial o necesita una licencia permisiva, abra un issue para hablar de la
licencia antes de adoptar la herramienta.

### Autor

Mikhail Deynekin — [GitHub: paulmann](https://github.com/paulmann) —
m@deynekin.com

### Informes de seguridad

No abra issues públicos para problemas de seguridad. Véase [SECURITY.md](SECURITY.md).

### Apoyar el proyecto

Si esta herramienta resolvió un problema de certificados, cítela en su runbook con la versión
y el enlace. No cree estrellas, forks ni comentarios automáticamente.
