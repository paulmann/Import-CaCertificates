# Import-CaCertificates
[![Versión](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates)
[![PowerShell](https://img.shields.io/badge/powershell-7.5%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Plataforma](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)

<!-- md-i18n:switcher -->
**En otros idiomas:** [English](README.md) · [Deutsch](README.de.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md) · Español · [Русский](README.ru.md)

- [1. Descripción general](#1-descripción-general)
- [2. Características principales](#2-características-principales)
- [3. Requisitos del sistema](#3-requisitos-del-sistema)
- [4. Guía de inicio rápido](#4-guía-de-inicio-rápido)
- [5. Instalación y configuración](#5-instalación-y-configuración)
- [6. Cómo funciona](#6-cómo-funciona)
- [7. Guía de integración con Let's Encrypt](#7-guía-de-integración-con-lets-encrypt)
- [8. Ejemplos de uso](#8-ejemplos-de-uso)
- [9. Referencia de parámetros](#9-referencia-de-parámetros)
- [10. Solución de problemas](#10-solución-de-problemas)
- [11. Licencia y agradecimientos](#11-licencia-y-agradecimientos)

***

## 1. Descripción general

**Import-CaCertificates** es una utilidad profesional de PowerShell diseñada para automatizar el proceso de descarga e importación de certificados de CA raíz e intermedios en el almacén de certificados de Windows. Resulta especialmente útil para servidores detrás de cortafuegos, despliegues automatizados y para corregir errores «Unknown CA» en servidores de correo como hMailServer y Exim.

### Propósito principal
El script garantiza que el entorno de Windows confíe en las autoridades de certificación necesarias mediante:
- La descarga segura de certificados desde URL directas.
- La importación de CA raíz en el almacén `Trusted Root Certification Authorities`.
- La importación de CA intermedias en el almacén `Intermediate Certification Authorities`.
- Una forma limpia y automatizada de mantener actualizadas las cadenas de confianza.

***

## 2. Características principales

- ✨ **Importación automatizada** - Gestiona tanto los certificados raíz como los intermedios en una sola pasada.
- 🔍 **Validación** - Verifica la integridad del certificado antes de la importación.
- 🛠️ **Seguridad administrativa** - Incluye comprobaciones de elevación para garantizar los permisos adecuados.
- 🔄 **Actualizaciones forzadas** - Opción para volver a importar certificados ya existentes.
- 📂 **Limpieza automática** - Elimina automáticamente los archivos temporales salvo que se indique lo contrario.
- 📝 **Registro detallado** - Comentarios paso a paso en la consola sobre el proceso de importación.

***

## 3. Requisitos del sistema

- **Sistema operativo**: Windows 7, Windows Server 2012 R2 o posterior.
- **PowerShell**: versión 7.5 o superior (compatible con PowerShell Core 7.x).
- **Permisos**: privilegios de administrador local (necesarios para modificar los almacenes de certificados del sistema).
- **Red**: acceso a Internet para descargar los certificados desde las URL de origen.

***

## 4. Guía de inicio rápido

### Paso 1: Descargar el script
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/paulmann/Import-CaCertificates/main/Import-CaCertificates.ps1" -OutFile "Import-CaCertificates.ps1"
```

### Paso 2: Ejecutar como administrador
Abra PowerShell como administrador y ejecute:
```powershell
.\Import-CaCertificates.ps1 -RootUrl "https://example.com/root.crt" -IntermediateUrl "https://example.com/intermediate.crt"
```

***

## 5. Instalación y configuración

1. Clone o descargue este repositorio.
2. Asegúrese de que `Set-ExecutionPolicy RemoteSigned` esté configurado para su sesión.
3. Coloque el script en su directorio de herramientas (por ejemplo, `C:\Scripts\`).

***

## 6. Cómo funciona

El script sigue un flujo de ejecución seguro:
1. **Comprobación de privilegios**: valida que el script se ejecute con derechos administrativos.
2. **Preparación del entorno**: crea un directorio temporal para el procesamiento de certificados.
3. **Fase de descarga**: obtiene los certificados mediante `Invoke-WebRequest`.
4. **Fase de importación**:
   - Certificados raíz -> `LocalMachine\Root`
   - Certificados intermedios -> `LocalMachine\CA`
5. **Limpieza**: elimina los archivos y objetos temporales.

***

## 7. Guía de integración con Let's Encrypt

Los certificados de Let's Encrypt suelen requerir que los servicios de Windows (como hMailServer o Exim) confíen en CA raíz e intermedias específicas.

### 7.1 Comandos típicos (Let's Encrypt ISRG Root X1)
Para confiar en la cadena estándar de Let's Encrypt:
```powershell
.\Import-CaCertificates.ps1 `
    -RootUrl "https://letsencrypt.org/certs/isrgrootx1.pem" `
    -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-r3.pem"
```

### 7.2 Comandos avanzados / adicionales (cadenas con firma cruzada)
Para entornos que requieren la antigua firma cruzada DST Root CA X3 (por compatibilidad heredada):
```powershell
.\Import-CaCertificates.ps1 `
    -RootUrl "https://letsencrypt.org/certs/isrg-root-x2.pem" `
    -IntermediateUrl "https://letsencrypt.org/certs/lets-encrypt-e1.pem" `
    -Force
```

***

## 8. Ejemplos de uso

### Importar solo una CA raíz
```powershell
.\Import-CaCertificates.ps1 -RootUrl "http://cacerts.digicert.com/DigiCertGlobalRootG2.crt"
```

### Importar conservando los archivos temporales (para depuración)
```powershell
.\Import-CaCertificates.ps1 -RootUrl "..." -KeepFiles
```

***

## 9. Referencia de parámetros

| Parámetro | Tipo | Obligatorio | Descripción |
|-----------|------|----------|-------------|
| `RootUrl` | String | **Sí** | URL del archivo del certificado de CA raíz (.crt, .cer, .pem). |
| `IntermediateUrl` | String | No | URL del archivo del certificado de CA intermedia. |
| `Force` | Switch | No | Fuerza la reimportación de los certificados aunque ya estén presentes. |
| `KeepFiles` | Switch | No | No elimina los archivos temporales al finalizar. |

***

## 10. Solución de problemas

- **Error: el script debe ejecutarse con privilegios elevados** - Haga clic con el botón derecho en PowerShell y elija «Ejecutar como administrador».
- **Unknown CA en hMailServer** - Después de ejecutar el script, reinicie el servicio hMailServer para que tome las nuevas CA de confianza.
- **Fallo en la descarga** - Asegúrese de que su cortafuegos permita solicitudes HTTPS salientes hacia el proveedor del certificado.

***

## 11. Licencia y agradecimientos

### Licencia
Este proyecto se distribuye bajo la **PolyForm Noncommercial License 1.0.0**.

### Copyright
Copyright © 2025 Mikhail Deynekin.
**Autor**: Mikhail Deynekin
- **Correo electrónico**: m@deynekin.com
- **GitHub**: [paulmann](https://github.com/paulmann)

***

## ⭐ Apoye el proyecto
Si esta herramienta le ayudó a resolver problemas de certificados, ¡dele una estrella en GitHub!
