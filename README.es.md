# Import-CaCertificates

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates/releases/latest)
[![PowerShell](https://img.shields.io/badge/powershell-7.4%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-lightgrey.svg)](LICENSE)

<!-- md-i18n:switcher -->
**Read this in:** [English](README.md) · [Deutsch](README.de.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md) · **Español** · [Русский](README.ru.md)

- [1. Descripción general](#1-descripción-general)
- [2. Qué cambió en 2.0.0](#2-qué-cambió-en-200)
- [3. Características](#3-características)
- [4. Modelo de seguridad](#4-modelo-de-seguridad)
- [5. Requisitos](#5-requisitos)
- [6. Instalación](#6-instalación)
- [7. Inicio rápido](#7-inicio-rápido)
- [8. Ejemplos de uso](#8-ejemplos-de-uso)
- [9. Parámetros](#9-parámetros)
- [10. Resultados de importación y códigos de salida](#10-resultados-de-importación-y-códigos-de-salida)
- [11. Migración desde la versión 1.x](#11-migración-desde-la-versión-1x)
- [12. Solución de problemas](#12-solución-de-problemas)
- [13. Desarrollo](#13-desarrollo)
- [14. Licencia y soporte](#14-licencia-y-soporte)

***

## 1. Descripción general

**Import-CaCertificates** importa certificados públicos de CA (raíz e intermedios) en los
almacenes de certificados de Windows. Está pensado para servidores detrás de firewalls
restrictivos y para implementaciones que deben confiar en una cadena de CA concreta — por
ejemplo hMailServer, Exim en Windows, IIS o una PKI corporativa interna.

La utilidad es deliberadamente limitada en su alcance: descarga o lee certificados públicos,
verifica que sean los certificados que esperas y los importa en los almacenes
`LocalMachine` o `CurrentUser`. No solicita, renueva, respalda, enumera ni elimina
certificados, y nunca importa claves privadas.

Importar una CA raíz es una decisión de confianza para toda la máquina. Por eso la versión
2.0.0 exige una huella SHA-256 esperada para cada certificado importado y rechaza la
importación de una CA raíz sin ella, salvo que se use el modificador explícito
`-AllowUnverifiedRoot`.

## 2. Qué cambió en 2.0.0

La versión 2.0.0 es una reescritura centrada en la seguridad. El comportamiento del comando
cambió de forma intencionada; consulta [CHANGELOG.md](CHANGELOG.md) y
[Migración desde la versión 1.x](#11-migración-desde-la-versión-1x) antes de actualizar.

- El único script se convirtió en un módulo (`Import-CaCertificate`) más un envoltorio CLI
  fino.
- Las importaciones de CA raíz requieren una huella SHA-256 fijada; el flujo antiguo solo con
  `-RootUrl` se rechaza en lugar de confiarse en silencio.
- Se rechazan las URL HTTP sin cifrar, los archivos PFX/P12 y los archivos con claves
  privadas.
- Los certificados se validan (periodo de validez, rol de CA, Key Usage, algoritmo de firma),
  y un par raíz/intermedio se comprueba contra la cadena antes de importar.
- Se admiten paquetes PEM con varios certificados, archivos locales y directorios.
- La deduplicación usa la huella SHA-256 (la huella SHA-1 se informa, pero no es la
  comprobación de identidad).
- Se añadieron resultados estructurados (`-PassThru`), informes JSON (`-Json`), archivos de
  registro (`-LogFile`), códigos de salida y CI con Pester/PSScriptAnalyzer.

## 3. Características

- **Anclaje explícito de la confianza**: cada certificado importado debe coincidir con una
  huella SHA-256 esperada que se pasa con `-Thumbprint`.
- **Valores predeterminados seguros para las CA raíz**: se rechaza la importación de una CA
  raíz sin huella; `-AllowUnverifiedRoot` es la anulación explícita, que se informa de forma
  destacada.
- **Solo HTTPS**: las URL `http://` se rechazan antes de realizar cualquier solicitud.
- **Solo certificados públicos**: se rechazan los archivos PFX/P12 y cualquier archivo que
  contenga una clave privada.
- **Validación**: análisis X.509, `NotBefore`/`NotAfter`, Basic Constraints `CA=true`,
  Key Usage `keyCertSign`, algoritmos de firma rotos (MD2/MD5) y tamaños de clave débiles.
- **Validación de la cadena**: cuando una raíz y un intermedio llegan en el mismo lote, el
  intermedio debe encadenarse con la raíz suministrada (`-SkipChainValidation` para omitirlo).
- **Entrada flexible**: URL HTTPS, archivo PEM/DER local, DER en base64, paquete PEM con varios
  certificados o un directorio de archivos de certificados.
- **Escrituras idempotentes en el almacén**: un certificado con la misma huella SHA-256 se
  omite; `-Force` reemplaza una copia existente, pero nunca omite la verificación.
- **Apto para automatización**: `-WhatIf`, `-Confirm`, `-PassThru`, `-Json`, `-LogFile`,
  `-LogLevel` y códigos de salida distintos.
- **Almacenes de Windows**: `LocalMachine` (predeterminado, con elevación) y `CurrentUser`,
  almacenes `Root`, `CA`, `AuthRoot` y `TrustedPeople`.

## 4. Modelo de seguridad

El modelo de amenazas completo está en [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md). La
versión breve:

1. **Solo se acepta HTTPS** para las descargas.
2. **La huella SHA-256 esperada es obligatoria** para cada certificado importado.
   Para una CA raíz es obligatoria a menos que se pase `-AllowUnverifiedRoot` de forma explícita.
3. **El certificado se valida antes de cualquier escritura en el almacén**: se analiza como
   X.509, está dentro de su periodo de validez, está marcado como CA, puede firmar certificados
   y está firmado con un algoritmo aceptable.
4. **El certificado no es una clave privada**: se rechazan los archivos que contienen claves
   privadas y los contenedores PFX/P12.
5. **La confirmación es lo predeterminado**: `ConfirmImpact = High` significa que una ejecución
   interactiva pregunta antes de escribir; la automatización no interactiva debe pasar
   `-Confirm:$false`.
6. **Sin telemetría ni acceso de red oculto**: las únicas solicitudes de red son los valores de
   `-Uri` que proporciones.

Una huella fijada protege contra una descarga sustituida, un espejo comprometido o un archivo
equivocado. No protege contra una CA que reemitió legítimamente una raíz distinta — por eso la
huella debe proceder de la página publicada por la propia CA o de la documentación de tu PKI,
no de la misma URL desde la que estás descargando.

## 5. Requisitos

| Requisito | Detalles |
|---|---|
| Sistema operativo | Windows 10 (1607 o posterior), Windows 11, Windows Server 2012 R2 o posterior |
| PowerShell | 7.4 o posterior (`pwsh`). Windows PowerShell 5.1 no es compatible. |
| Permisos | Administrador local para `-StoreLocation LocalMachine`; sin elevación para `-StoreLocation CurrentUser` |
| Red | Acceso HTTPS a cada host de `-Uri`; no se necesita con `-Path` |
| Windows 7 / 8.1 | No compatible: PowerShell 7 no se instala allí. La versión 1.x afirmaba una compatibilidad que no tenía. |

Probado por CI en `windows-latest` con PowerShell 7.x y Pester 5.7.1, y localmente en
Windows 10/11 con PowerShell 7.6. Se espera que otras combinaciones funcionen, pero CI no las
cubre.

## 6. Instalación

### Desde una versión publicada (recomendado)

Descarga el último `Import-CaCertificates-<version>.zip` y `SHA256SUMS.txt` desde la
[página de versiones](https://github.com/paulmann/Import-CaCertificates/releases/latest),
verifica el archivo y extráelo en un directorio de herramientas como
`C:\Tools\Import-CaCertificates`:

```powershell
$expected = (Select-String -Path .\SHA256SUMS.txt -Pattern '\.zip$').Line.Split(' ')[0]
(Get-FileHash -Algorithm SHA256 -LiteralPath .\Import-CaCertificates-2.0.0.zip).Hash -eq $expected
Expand-Archive -LiteralPath .\Import-CaCertificates-2.0.0.zip -DestinationPath C:\Tools\Import-CaCertificates
```

El archivo contiene el módulo (`src/Import-CaCertificates`), el envoltorio CLI, la
documentación y la licencia. El envoltorio localiza el módulo en relación consigo mismo, por lo
que el directorio extraído puede moverse como un todo.

### Desde el código fuente

```powershell
git clone https://github.com/paulmann/Import-CaCertificates.git
cd Import-CaCertificates
```

Todavía no hay instalador ni paquete en PSGallery. Importa el módulo directamente:

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Command Import-CaCertificate
```

### Verificación

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Help Import-CaCertificate -Full
```

## 7. Inicio rápido

**Paso 1 — obtén la huella SHA-256 esperada de la página publicada por la CA.** Si la CA
publica el archivo del certificado, calcula la huella tú mismo y compárala con el valor que la
CA publica en otro lugar:

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

`96BCEC06…` es la huella SHA-256 de ISRG Root X1 tal como la publica Let's Encrypt; se muestra
aquí como ejemplo funcional, no como recomendación de confiar en ninguna CA.

**Paso 3 — importación.** Sin `-Confirm:$false`, una sesión interactiva pide confirmación antes
de cada escritura en el almacén. La automatización debe pasar `-Confirm:$false`:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru
```

**Paso 4 — verifica el almacén.**

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG Root X1'
```

Reinicia el servicio que informó de la CA desconocida (por ejemplo hMailServer) para que vuelva
a leer el almacén de confianza de la máquina.

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

Un PEM con varios certificados puede contener una raíz y uno o varios intermedios. Fija cada
certificado que importes; `-NoRootImport` omite la raíz:

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

`-Json` devuelve un único envoltorio JSON (`Version`, `Timestamp`, `Summary`, `Results`). Con
`-Json` el registro de información se suprime a menos que se pase `-LogLevel` de forma
explícita, así que stdout contiene solo el documento JSON.

### Registrar en un archivo

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' `
    -LogFile 'C:\logs\ca-import.log' -LogLevel Verbose -Confirm:$false
```

### Host sin conexión / aislado

1. Descarga el certificado en otra máquina y verifica su huella.
2. Copia el archivo PEM/DER (y su SHA-256) al host de destino.
3. Ejecuta `Import-CaCertificate -Path ... -Thumbprint ... -Confirm:$false`.

### Reemplazar una copia existente

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' -Force -Confirm:$false
```

`-Force` reemplaza un certificado con la misma huella SHA-256; no omite la comprobación de
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
| `-Uri` | string[] | — | URL HTTPS del archivo o archivos de certificado (PEM, DER, DER en base64 o un paquete PEM con varios certificados). Obligatorio en el conjunto de parámetros `ByUri`. |
| `-Path` | string[] | — | Archivo o archivos de certificado locales, o directorios de archivos `.cer/.crt/.pem/.der/.cert`. Obligatorio en el conjunto de parámetros `ByPath`. |
| `-Thumbprint` | string[] | — | Huella o huellas SHA-256 esperadas, 64 caracteres hexadecimales; los espacios, los dos puntos y los guiones se ignoran. Cada certificado importado debe coincidir con uno de los valores. |
| `-StoreLocation` | string | `LocalMachine` | `LocalMachine` (requiere elevación) o `CurrentUser`. |
| `-StoreName` | string | auto | `Root`, `CA`, `AuthRoot` o `TrustedPeople`. Sin él, una CA autofirmada va a `Root` y una CA no autofirmada a `CA`. |
| `-NoRootImport` | switch | off | Omitir los certificados de CA raíz en lugar de importarlos. |
| `-AllowUnverifiedRoot` | switch | off | Permitir la importación de una CA raíz sin `-Thumbprint`. Decisión de confianza explícita; se registra una advertencia y la ejecución se informa como no verificada. |
| `-RequireConfirmation` | switch | off | Pedir una confirmación interactiva de sí/no para cada certificado, además de `ShouldProcess`. No se puede usar en sesiones no interactivas. |
| `-Force` | switch | off | Reemplazar un certificado existente con la misma huella SHA-256. |
| `-PassThru` | switch | off | Devolver un objeto de resultado por certificado. |
| `-Json` | switch | off | Devolver un único envoltorio JSON (`Version`, `Timestamp`, `Summary`, `Results`). |
| `-LogLevel` | string | `Info` | `None`, `Error`, `Warning`, `Info` o `Verbose`. |
| `-LogFile` | string | — | Añadir líneas de registro (UTF-8, sin BOM) a este archivo. |
| `-KeepTempFiles` | switch | off | Conservar los archivos descargados en el directorio temporal. |
| `-TempPath` | string | `$env:TEMP` | Directorio principal de un directorio temporal de descarga único, que se elimina después. Los archivos existentes nunca se eliminan. |
| `-SkipChainValidation` | switch | off | Omitir la comprobación de la cadena de firmas entre las raíces y los intermedios suministrados. |
| `-WhatIf` / `-Confirm` | common | — | Comportamiento estándar de `ShouldProcess`. |

### Envoltorio CLI `Import-CaCertificates.ps1`

El envoltorio acepta los mismos parámetros más dos modificadores de compatibilidad obsoletos
asignados a `-Uri`:

| Parámetro | Estado | Descripción |
|---|---|---|
| `-RootUrl` | obsoleto | URL HTTPS de un certificado de CA raíz. Usa `-Uri`. |
| `-IntermediateUrl` | obsoleto | URL HTTPS de un certificado de CA intermedia. Usa `-Uri`. |
| `-KeepFiles` | alias | Alias de `-KeepTempFiles` (el README de 1.x usaba este nombre). |

El envoltorio debe iniciarse desde un directorio de versión extraído (o la raíz del
repositorio); carga `src/Import-CaCertificates/Import-CaCertificates.psd1` en relación con su
propia ubicación.

## 10. Resultados de importación y códigos de salida

Cada certificado produce uno de los siguientes estados:

| Estado | Significado |
|---|---|
| `Imported` | Certificado escrito en el almacén de destino y verificado leyéndolo de nuevo. |
| `Replaced` | Se reemplazó un certificado existente con la misma huella SHA-256 (`-Force`). |
| `AlreadyPresent` | El mismo certificado ya está en el almacén; no se escribió nada. |
| `Skipped` | El certificado se excluyó por política (`-NoRootImport`). |
| `WhatIf` | Simulación: el certificado superó todas las comprobaciones, pero no se escribió. |
| `Declined` | La confirmación interactiva se respondió con «no». |

Códigos de salida de la CLI:

| Código | Significado |
|---|---|
| `0` | La ejecución terminó (incluidas las simulaciones, los duplicados omitidos y las confirmaciones rechazadas). Verifica el almacén antes de considerarlo «importado». |
| `1` | Fallo operativo: descarga, sistema de archivos, acceso al almacén, módulo no encontrado. |
| `2` | Rechazo de seguridad o de validación: HTTP simple, huella ausente o fallida, no es una CA, expirado, clave privada, PFX, cadena no coincidente, sin elevación para `LocalMachine`. |

## 11. Migración desde la versión 1.x

| 1.x | 2.0.0 |
|---|---|
| `-RootUrl` y `-IntermediateUrl` | `-Uri` (una lista); los nombres obsoletos siguen funcionando en el envoltorio CLI y registran una advertencia. |
| Sin comprobación de huella | `-Thumbprint` es obligatorio para cada certificado; las importaciones de CA raíz se rechazan sin él salvo que se use `-AllowUnverifiedRoot`. |
| `-KeepFiles` (documentado) / `-KeepTempFiles` (implementado) | `-KeepTempFiles`; `-KeepFiles` es un alias. |
| `-TempPath` se eliminaba después de la ejecución | Se crea un subdirectorio único bajo `-TempPath` y se elimina; los archivos existentes no se tocan. |
| Un solo certificado por URL | Se admiten paquetes PEM con varios certificados, directorios y `-Path`. |
| Raíz/intermedio elegidos por parámetro | Se eligen por el tipo de certificado, o se fuerzan con `-StoreName`. |
| Afirmación de compatibilidad con Windows 7 / Server 2012 R2 | Windows 10 1607+/11, Windows Server 2012 R2+ con PowerShell 7.4+. Windows 7 no es compatible. |
| Solo registro en consola | `-PassThru`, `-Json`, `-LogFile`, `-LogLevel` y códigos de salida. |

## 12. Solución de problemas

| Síntoma | Causa | Acción |
|---|---|---|
| `Root CA import ... requires an expected SHA-256 fingerprint` | CA raíz importada sin `-Thumbprint` | Obtén la huella de la página publicada por la CA y pásala. |
| `Invalid -Thumbprint value ... SHA-1 thumbprint` | El valor es una huella SHA-1 de 40 caracteres hexadecimales | Calcula la huella SHA-256 (64 caracteres hexadecimales). |
| `does not match any expected -Thumbprint value` | Certificado equivocado o huella equivocada | Compara el sujeto, el emisor y el SHA-256 impreso con el origen. |
| `Only https:// URLs are allowed` | URL `http://` | Usa la URL HTTPS de la CA; no eludas la comprobación. |
| `contains a private key` / `PFX/P12` | El archivo contiene material de clave privada | Exporta el certificado público (`Export-Certificate -Type CERT`) e importa ese. |
| `failed validation: the certificate is expired` | Certificado expirado | Obtén el certificado actual de la CA. |
| `does not chain to the supplied root certificate(s)` | La raíz y el intermedio no se corresponden | Descarga el par correspondiente o importa solo el certificado que necesites. |
| `LocalMachine certificate stores require an elevated session` | No se ejecuta como administrador | Inicia un `pwsh` con elevación o usa `-StoreLocation CurrentUser`. |
| `NonInteractive mode` error | Petición de confirmación predeterminada en automatización | Pasa `-Confirm:$false` (y `-WhatIf` para simulaciones). |
| `Unknown CA` remains after import | El servicio dependiente almacenó en caché su cadena | Reinicia el servicio. |

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

Las pruebas de integración están condicionadas: las pruebas de red se ejecutan cuando
`$env:CI` está definido, y las pruebas de LocalMachine solo se ejecutan en un runner de CI con
elevación. Consulta
[tests/Import-CaCertificates.Integration.Tests.ps1](tests/Import-CaCertificates.Integration.Tests.ps1).

CI ejecuta PSScriptAnalyzer y Pester en cada push y pull request; al empujar una etiqueta `v*`
se compila el archivo, se verifica su SHA-256 y se publica la versión de GitHub.

## 14. Licencia y soporte

### Licencia

Este proyecto tiene la licencia **PolyForm Noncommercial License 1.0.0** — consulta
[LICENSE](LICENSE). El uso comercial requiere una licencia aparte; contacta con el autor.
Si tu caso de uso es comercial o necesitas una licencia permisiva, abre un issue para hablar
de licencias antes de adoptar la herramienta.

### Autor

Mikhail Deynekin — [GitHub: paulmann](https://github.com/paulmann) —
m@deynekin.com

### Informes de seguridad

No abras issues públicos para problemas de seguridad. Consulta [SECURITY.md](SECURITY.md).

### Apoyar el proyecto

Si esta herramienta te resolvió un problema de certificados, cítala en tu runbook con la
versión y el enlace. No crees estrellas, forks ni comentarios automáticamente.
