# Import-CaCertificates

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/paulmann/Import-CaCertificates/releases/latest)
[![PowerShell](https://img.shields.io/badge/powershell-7.4%2B-blue.svg)](https://learn.microsoft.com/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows-blue.svg)](https://www.microsoft.com/windows/)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-lightgrey.svg)](LICENSE)

<!-- md-i18n:switcher -->
**Read this in:** [English](README.md) · [Deutsch](README.de.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md) · [Español](README.es.md) · **Русский**

- [1. Обзор](#1-обзор)
- [2. Что изменилось в 2.0.0](#2-что-изменилось-в-200)
- [3. Возможности](#3-возможности)
- [4. Модель безопасности](#4-модель-безопасности)
- [5. Требования](#5-требования)
- [6. Установка](#6-установка)
- [7. Быстрый старт](#7-быстрый-старт)
- [8. Примеры использования](#8-примеры-использования)
- [9. Параметры](#9-параметры)
- [10. Результаты импорта и коды выхода](#10-результаты-импорта-и-коды-выхода)
- [11. Миграция с 1.x](#11-миграция-с-1x)
- [12. Устранение неполадок](#12-устранение-неполадок)
- [13. Разработка](#13-разработка)
- [14. Лицензия и поддержка](#14-лицензия-и-поддержка)

***

## 1. Обзор

**Import-CaCertificates** импортирует публичные сертификаты CA (Root и Intermediate) в
хранилища сертификатов Windows. Инструмент предназначен для серверов за строгими
межсетевыми экранами и для развёртываний, которые должны доверять конкретной цепочке CA, —
например, hMailServer, Exim на Windows, IIS или внутренняя корпоративная PKI.

Утилита намеренно узка по назначению: она скачивает или читает публичные сертификаты,
проверяет, что это именно те сертификаты, которые вы ожидаете, и импортирует их в
хранилища `LocalMachine` или `CurrentUser`. Она не запрашивает, не продлевает, не создаёт
резервные копии, не выводит список и не удаляет сертификаты и никогда не импортирует
закрытые ключи.

Импорт корневого CA — это решение о доверии в масштабе всей машины. Поэтому версия 2.0.0
требует ожидаемый отпечаток SHA-256 для каждого импортируемого сертификата и отказывает в
импорте корневого CA без него, если только не указан явный переключатель
`-AllowUnverifiedRoot`.

## 2. Что изменилось в 2.0.0

Версия 2.0.0 — переписывание с упором на безопасность. Поведение команды изменено
намеренно; перед обновлением смотрите [CHANGELOG.md](CHANGELOG.md) и
[Миграция с 1.x](#11-миграция-с-1x).

- Единственный скрипт стал модулем (`Import-CaCertificate`) плюс тонкая обёртка CLI.
- Импорт корневого CA требует закреплённого отпечатка SHA-256; старый сценарий только с
  `-RootUrl` отклоняется, а не принимается молча.
- URL по простому HTTP, файлы PFX/P12 и файлы, содержащие закрытые ключи, отклоняются.
- Сертификаты проверяются (срок действия, роль CA, Key Usage, алгоритм подписи), а пара
  Root/Intermediate проверяется по цепочке перед импортом.
- Поддерживаются PEM-пакеты с несколькими сертификатами, локальные файлы и каталоги.
- Дедупликация выполняется по отпечатку SHA-256 (отпечаток SHA-1 выводится, но проверкой
  идентичности не является).
- Добавлены структурированные результаты (`-PassThru`), отчёты JSON (`-Json`), файлы
  журналов (`-LogFile`), коды выхода и CI на Pester/PSScriptAnalyzer.

## 3. Возможности

- **Явная привязка доверия**: каждый импортируемый сертификат должен совпадать с ожидаемым
  отпечатком SHA-256, переданным через `-Thumbprint`.
- **Безопасные значения по умолчанию для корневых CA**: импорт корневого CA без отпечатка
  отклоняется; `-AllowUnverifiedRoot` — явное, громко отражаемое в журнале переопределение.
- **Только HTTPS**: URL `http://` отклоняются до выполнения любого запроса.
- **Только публичные сертификаты**: файлы PFX/P12 и любой файл, содержащий закрытый ключ,
  отклоняются.
- **Проверка**: разбор X.509, `NotBefore`/`NotAfter`, Basic Constraints `CA=true`,
  Key Usage `keyCertSign`, сломанные алгоритмы подписи (MD2/MD5) и слабые размеры ключа.
- **Проверка цепочки**: когда корневой и промежуточный сертификаты приходят в одном пакете,
  промежуточный должен выстраиваться в цепочку к переданному корневому
  (`-SkipChainValidation` — отказ от проверки).
- **Гибкий ввод**: URL HTTPS, локальный файл PEM/DER, DER в base64, PEM-пакет с несколькими
  сертификатами или каталог с файлами сертификатов.
- **Идемпотентная запись в хранилище**: сертификат с тем же отпечатком SHA-256 пропускается;
  `-Force` заменяет существующую копию, но никогда не пропускает проверку.
- **Дружелюбность к автоматизации**: `-WhatIf`, `-Confirm`, `-PassThru`, `-Json`, `-LogFile`,
  `-LogLevel` и различимые коды выхода.
- **Хранилища Windows**: `LocalMachine` (по умолчанию, с повышением прав) и `CurrentUser`,
  хранилища `Root`, `CA`, `AuthRoot` и `TrustedPeople`.

## 4. Модель безопасности

Полная модель угроз — в [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md). Кратко:

1. **Принимается только HTTPS** для загрузок.
2. **Ожидаемый отпечаток SHA-256 обязателен** для каждого импортируемого сертификата.
   Для корневого CA он обязателен, если явно не передан `-AllowUnverifiedRoot`.
3. **Сертификат проверяется до любой записи в хранилище**: разбирается как X.509, находится
   в пределах срока действия, помечен как CA, имеет право подписывать сертификаты и подписан
   приемлемым алгоритмом.
4. **Сертификат не является закрытым ключом**: файлы, содержащие закрытые ключи, и
   контейнеры PFX/P12 отклоняются.
5. **Подтверждение — это поведение по умолчанию**: `ConfirmImpact = High` означает, что
   интерактивный запуск спрашивает перед записью; неинтерактивная автоматизация должна
   передавать `-Confirm:$false`.
6. **Нет телеметрии, нет скрытого сетевого доступа**: единственные сетевые запросы — это
   переданные вами значения `-Uri`.

Закреплённый отпечаток защищает от подменённой загрузки, скомпрометированного зеркала или
неверного файла. Он не защищает от CA, который правомерно выпустил другой корневой
сертификат, — поэтому отпечаток должен браться с собственной опубликованной страницы CA или
из документации вашей PKI, а не с того же URL, с которого вы скачиваете.

## 5. Требования

| Требование | Подробности |
|---|---|
| Операционная система | Windows 10 (1607 или новее), Windows 11, Windows Server 2012 R2 или новее |
| PowerShell | 7.4 или новее (`pwsh`). Windows PowerShell 5.1 не поддерживается. |
| Права | Локальный администратор для `-StoreLocation LocalMachine`; повышение прав не нужно для `-StoreLocation CurrentUser` |
| Сеть | Доступ по HTTPS к каждому хосту из `-Uri`; не требуется при `-Path` |
| Windows 7 / 8.1 | Не поддерживаются: PowerShell 7 там не устанавливается. Версия 1.x заявляла поддержку, которой не имела. |

Проверено в CI на `windows-latest` с PowerShell 7.x и Pester 5.7.1, а также локально на
Windows 10/11 с PowerShell 7.6. Ожидается, что другие комбинации работают, но CI их не
покрывает.

## 6. Установка

### Из релиза (рекомендуется)

Скачайте последний `Import-CaCertificates-<version>.zip` и `SHA256SUMS.txt` со
[страницы Releases](https://github.com/paulmann/Import-CaCertificates/releases/latest),
проверьте архив и распакуйте его в каталог инструментов, например
`C:\Tools\Import-CaCertificates`:

```powershell
$expected = (Select-String -Path .\SHA256SUMS.txt -Pattern '\.zip$').Line.Split(' ')[0]
(Get-FileHash -Algorithm SHA256 -LiteralPath .\Import-CaCertificates-2.0.0.zip).Hash -eq $expected
Expand-Archive -LiteralPath .\Import-CaCertificates-2.0.0.zip -DestinationPath C:\Tools\Import-CaCertificates
```

Архив содержит модуль (`src/Import-CaCertificates`), обёртку CLI, документацию и лицензию.
Обёртка находит модуль относительно себя, поэтому распакованный каталог можно перемещать
целиком.

### Из исходного кода

```powershell
git clone https://github.com/paulmann/Import-CaCertificates.git
cd Import-CaCertificates
```

Установщика и пакета в PSGallery пока нет. Импортируйте модуль напрямую:

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Command Import-CaCertificate
```

### Проверка

```powershell
Import-Module .\src\Import-CaCertificates\Import-CaCertificates.psd1
Get-Help Import-CaCertificate -Full
```

## 7. Быстрый старт

**Шаг 1 — получите ожидаемый отпечаток SHA-256 с опубликованной страницы CA.** Если CA
публикует файл сертификата, вычислите отпечаток сами и сравните его со значением, которое CA
публикует в другом месте:

```powershell
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new('C:\certs\ca.pem')
[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($cert.RawData))
```

**Шаг 2 — пробный прогон.** `-WhatIf` скачивает, разбирает, проверяет и печатает план; в
хранилище он не пишет:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -WhatIf -Confirm:$false
```

`96BCEC06…` — это отпечаток SHA-256 сертификата ISRG Root X1 в публикации Let's Encrypt; он
приведён здесь как рабочий пример, а не как рекомендация доверять какому-либо CA.

**Шаг 3 — импорт.** Без `-Confirm:$false` интерактивный сеанс запрашивает подтверждение перед
каждой записью в хранилище. Автоматизация должна передавать `-Confirm:$false`:

```powershell
Import-CaCertificate -Uri 'https://letsencrypt.org/certs/isrgrootx1.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -Confirm:$false -PassThru
```

**Шаг 4 — проверьте хранилище.**

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match 'ISRG Root X1'
```

Перезапустите службу, которая сообщала о неизвестном CA (например, hMailServer), чтобы она
перечитала хранилище доверенных сертификатов машины.

## 8. Примеры использования

### Импорт корневого CA из локального файла

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' `
    -Thumbprint '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6' `
    -StoreLocation LocalMachine -Confirm:$false
```

### Импорт только промежуточного CA

Сертификат CA, не являющийся самоподписанным, автоматически направляется в `LocalMachine\CA`:

```powershell
Import-CaCertificate -Path 'C:\certs\intermediate.pem' -Thumbprint '<sha256>' -Confirm:$false
```

### Импорт пакета с пропуском корневого сертификата

PEM-пакет с несколькими сертификатами может содержать корневой и один или несколько
промежуточных. Закрепите каждый импортируемый сертификат; `-NoRootImport` пропускает
корневой:

```powershell
Import-CaCertificate -Path 'C:\certs\chain.pem' `
    -Thumbprint '<sha256-intermediate-1>', '<sha256-intermediate-2>' `
    -NoRootImport -Confirm:$false
```

### Импорт каталога с сертификатами

```powershell
Import-CaCertificate -Path 'C:\certs\corporate-cas' -Thumbprint '<sha256-1>', '<sha256-2>' -WhatIf -Confirm:$false
```

### Автоматизация с отчётом JSON

```powershell
$report = Import-CaCertificate -Uri 'https://ca.example.com/root.pem' `
    -Thumbprint '0123...' -Confirm:$false -Json
$report | Out-File -LiteralPath 'C:\logs\ca-import.json' -Encoding utf8NoBOM
```

`-Json` возвращает один конверт JSON (`Version`, `Timestamp`, `Summary`, `Results`). При
`-Json` информационный журнал подавляется, если `-LogLevel` не передан явно, поэтому stdout
содержит только документ JSON.

### Запись журнала в файл

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' `
    -LogFile 'C:\logs\ca-import.log' -LogLevel Verbose -Confirm:$false
```

### Офлайн-хост / изолированный сегмент

1. Скачайте сертификат на другой машине и проверьте его отпечаток.
2. Скопируйте файл PEM/DER (и его SHA-256) на целевой хост.
3. Выполните `Import-CaCertificate -Path ... -Thumbprint ... -Confirm:$false`.

### Замена существующей копии

```powershell
Import-CaCertificate -Path 'C:\certs\root.pem' -Thumbprint '<sha256>' -Force -Confirm:$false
```

`-Force` заменяет сертификат с тем же отпечатком SHA-256; он не обходит проверку отпечатка.

### Отмена импорта

```powershell
Remove-Item -Path Cert:\LocalMachine\Root\<SHA-1-thumbprint>
Remove-Item -Path Cert:\LocalMachine\CA\<SHA-1-thumbprint>
```

Каждый объект результата сообщает `ThumbprintSha1` (для `certmgr.msc` / `certutil`) и
`ThumbprintSha256` (проверка идентичности).

Другие сценарии: [docs/EXAMPLES.md](docs/EXAMPLES.md).

## 9. Параметры

### Команда модуля `Import-CaCertificate`

| Параметр | Тип | По умолчанию | Описание |
|---|---|---|---|
| `-Uri` | string[] | — | URL HTTPS файлов сертификатов (PEM, DER, DER в base64 или PEM-пакет с несколькими сертификатами). Обязателен в наборе параметров `ByUri`. |
| `-Path` | string[] | — | Локальные файлы сертификатов или каталоги с файлами `.cer/.crt/.pem/.der/.cert`. Обязателен в наборе параметров `ByPath`. |
| `-Thumbprint` | string[] | — | Ожидаемые отпечатки SHA-256, 64 шестнадцатеричных символа; пробелы, двоеточия и дефисы игнорируются. Каждый импортируемый сертификат должен совпасть с одним из значений. |
| `-StoreLocation` | string | `LocalMachine` | `LocalMachine` (требует повышения прав) или `CurrentUser`. |
| `-StoreName` | string | авто | `Root`, `CA`, `AuthRoot` или `TrustedPeople`. Без него самоподписанный CA попадает в `Root`, а несамоподписанный CA — в `CA`. |
| `-NoRootImport` | switch | выкл. | Пропускать сертификаты корневых CA вместо их импорта. |
| `-AllowUnverifiedRoot` | switch | выкл. | Разрешить импорт корневого CA без `-Thumbprint`. Явное решение о доверии; в журнал пишется предупреждение, а прогон помечается как непроверенный. |
| `-RequireConfirmation` | switch | выкл. | Запрашивать интерактивное подтверждение да/нет для каждого сертификата дополнительно к `ShouldProcess`. Неприменимо в неинтерактивных сеансах. |
| `-Force` | switch | выкл. | Заменить существующий сертификат с тем же отпечатком SHA-256. |
| `-PassThru` | switch | выкл. | Возвращать один объект результата на каждый сертификат. |
| `-Json` | switch | выкл. | Возвращать один конверт JSON (`Version`, `Timestamp`, `Summary`, `Results`). |
| `-LogLevel` | string | `Info` | `None`, `Error`, `Warning`, `Info` или `Verbose`. |
| `-LogFile` | string | — | Дописывать строки журнала (UTF-8, без BOM) в этот файл. |
| `-KeepTempFiles` | switch | выкл. | Сохранять скачанные файлы во временном каталоге. |
| `-TempPath` | string | `$env:TEMP` | Родительский каталог для уникального временного каталога загрузки, который затем удаляется. Существующие файлы никогда не удаляются. |
| `-SkipChainValidation` | switch | выкл. | Пропустить проверку цепочки подписей между переданными корневыми и промежуточными сертификатами. |
| `-WhatIf` / `-Confirm` | общие | — | Стандартное поведение `ShouldProcess`. |

### Обёртка CLI `Import-CaCertificates.ps1`

Обёртка принимает те же параметры плюс два устаревших переключателя совместимости,
отображаемых на `-Uri`:

| Параметр | Статус | Описание |
|---|---|---|
| `-RootUrl` | устарел | URL HTTPS сертификата корневого CA. Используйте `-Uri`. |
| `-IntermediateUrl` | устарел | URL HTTPS сертификата промежуточного CA. Используйте `-Uri`. |
| `-KeepFiles` | псевдоним | Псевдоним `-KeepTempFiles` (в README версии 1.x использовалось это имя). |

Обёртку нужно запускать из распакованного каталога релиза (или из корня репозитория); она
загружает `src/Import-CaCertificates/Import-CaCertificates.psd1` относительно собственного
расположения.

## 10. Результаты импорта и коды выхода

Каждый сертификат даёт один из следующих статусов:

| Статус | Значение |
|---|---|
| `Imported` | Сертификат записан в целевое хранилище и проверен обратным чтением. |
| `Replaced` | Существующий сертификат с тем же отпечатком SHA-256 заменён (`-Force`). |
| `AlreadyPresent` | Тот же сертификат уже есть в хранилище; ничего не записано. |
| `Skipped` | Сертификат исключён по правилу (`-NoRootImport`). |
| `WhatIf` | Пробный прогон: сертификат прошёл все проверки, но не был записан. |
| `Declined` | На интерактивное подтверждение ответили «нет». |

Коды выхода CLI:

| Код | Значение |
|---|---|
| `0` | Прогон завершён (включая пробные прогоны, пропущенные дубликаты и отклонённые подтверждения). Проверьте хранилище, прежде чем считать это «импортировано». |
| `1` | Операционный сбой: загрузка, файловая система, доступ к хранилищу, модуль не найден. |
| `2` | Отказ по безопасности или проверке: простой HTTP, отсутствующий или несовпавший отпечаток, не CA, истёк срок, закрытый ключ, PFX, несовпадение цепочки, нет повышения прав для `LocalMachine`. |

## 11. Миграция с 1.x

| 1.x | 2.0.0 |
|---|---|
| `-RootUrl` и `-IntermediateUrl` | `-Uri` (список); устаревшие имена по-прежнему работают в обёртке CLI и пишут предупреждение в журнал. |
| Проверки отпечатка нет | `-Thumbprint` обязателен для каждого сертификата; импорт корневого CA отклоняется без него, если не используется `-AllowUnverifiedRoot`. |
| `-KeepFiles` (в документации) / `-KeepTempFiles` (в реализации) | `-KeepTempFiles`; `-KeepFiles` — псевдоним. |
| `-TempPath` удаляется после прогона | Под `-TempPath` создаётся уникальный подкаталог и удаляется; существующие файлы не затрагиваются. |
| Один сертификат на URL | Поддерживаются PEM-пакеты с несколькими сертификатами, каталоги и `-Path`. |
| Корневой/промежуточный выбирается параметром | Выбирается по типу сертификата или принудительно через `-StoreName`. |
| Заявление о Windows 7 / Server 2012 R2 | Windows 10 1607+/11, Windows Server 2012 R2+ с PowerShell 7.4+. Windows 7 не поддерживается. |
| Только вывод в консоль | `-PassThru`, `-Json`, `-LogFile`, `-LogLevel` и коды выхода. |

## 12. Устранение неполадок

| Симптом | Причина | Действие |
|---|---|---|
| `Root CA import ... requires an expected SHA-256 fingerprint` | Корневой CA импортируется без `-Thumbprint` | Возьмите отпечаток с опубликованной страницы CA и передайте его. |
| `Invalid -Thumbprint value ... SHA-1 thumbprint` | Значение — 40-символьный отпечаток SHA-1 | Вычислите отпечаток SHA-256 (64 шестнадцатеричных символа). |
| `does not match any expected -Thumbprint value` | Неверный сертификат или неверный отпечаток | Сравните subject, issuer и напечатанный SHA-256 с источником. |
| `Only https:// URLs are allowed` | URL `http://` | Используйте URL HTTPS этого CA; не обходите проверку. |
| `contains a private key` / `PFX/P12` | Файл содержит материал закрытого ключа | Экспортируйте публичный сертификат (`Export-Certificate -Type CERT`) и импортируйте его. |
| `failed validation: the certificate is expired` | Истёкший сертификат | Получите актуальный сертификат у CA. |
| `does not chain to the supplied root certificate(s)` | Корневой и промежуточный сертификаты не подходят друг другу | Скачайте соответствующую пару или импортируйте только нужный сертификат. |
| `LocalMachine certificate stores require an elevated session` | Запуск не от имени администратора | Запустите `pwsh` с повышением прав или используйте `-StoreLocation CurrentUser`. |
| Ошибка `NonInteractive mode` | Запрос подтверждения по умолчанию в автоматизации | Передайте `-Confirm:$false` (и `-WhatIf` для пробных прогонов). |
| `Unknown CA` остаётся после импорта | Зависимая служба закешировала свою цепочку | Перезапустите службу. |

## 13. Разработка

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

Интеграционные тесты включаются по условию: сетевые тесты выполняются, когда задан
`$env:CI`, а тесты LocalMachine — только на CI-агенте с повышенными правами. См.
[tests/Import-CaCertificates.Integration.Tests.ps1](tests/Import-CaCertificates.Integration.Tests.ps1).

CI запускает PSScriptAnalyzer и Pester на каждый push и pull request; push тега `v*`
собирает архив, проверяет его SHA-256 и публикует релиз на GitHub.

## 14. Лицензия и поддержка

### Лицензия

Проект лицензирован по **PolyForm Noncommercial License 1.0.0** — см.
[LICENSE](LICENSE). Коммерческое использование требует отдельной лицензии; обратитесь к
автору. Если ваш сценарий коммерческий или вам нужна разрешительная лицензия, откройте
issue для обсуждения лицензирования до внедрения инструмента.

### Автор

Mikhail Deynekin — [GitHub: paulmann](https://github.com/paulmann) —
m@deynekin.com

### Сообщения об уязвимостях

Пожалуйста, не открывайте публичные issue по проблемам безопасности. См.
[SECURITY.md](SECURITY.md).

### Поддержка проекта

Если этот инструмент помог вам решить проблему с сертификатами, упомяните его в своём
runbook с указанием версии и ссылки. Не создавайте звёзды, форки и комментарии автоматически.
