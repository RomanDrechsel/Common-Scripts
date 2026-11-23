# Remote SSH / rsync Helper

[![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)

[🇬🇧 English](README.md) | **🇩🇪 Deutsch**

Ein wiederverwendbarer **Bash-Helper zum Hochladen einzelner Dateien und zum Synchronisieren von Verzeichnissen mit einem Linux-Server**. Die Übertragung erfolgt mit `rsync` über SSH. Der Helper kann in andere Shell-Skripte eingebunden oder direkt für das Deployment eines Projektverzeichnisses ausgeführt werden.

> **Hinweis zum Protokoll:** Das Skript verwendet **rsync über SSH**, nicht das SFTP-Protokoll. Beide können SSH als sichere Verbindung nutzen, allerdings muss `rsync` auch auf dem Zielserver installiert sein.

## Funktionen

- Einzelne Dateien hochladen; fehlende Zielverzeichnisse werden automatisch angelegt.
- Verzeichnisse synchronisieren und dabei nur Änderungen übertragen.
- Synchronisierung mit `--dry-run` **unverbindlich testen**, ohne Dateien auf dem Server zu verändern.
- Dateien und Ordner über rsync-Ausschlussmuster auslassen.
- Optional nach erfolgreicher Projektsynchronisierung eine Marker-Datei auf dem Server aktualisieren.
- Fehler durch Rückgabecodes an aufrufende Skripte weitergeben.
- Unsichere relative Remote-Pfade ablehnen und das Zielverzeichnis prüfen.

## Voraussetzungen

- Bash ab Version 4.3 (wegen `local -n`).
- `rsync` **lokal und auf dem Zielserver**.
- OpenSSH-Client (`ssh`) auf dem lokalen Rechner und SSH-Zugriff auf den Server.
- Ausreichende Berechtigungen, um Dateien und Verzeichnisse unterhalb des konfigurierten Zielverzeichnisses anzulegen.

Für automatisierte Deployments empfiehlt sich die Authentifizierung per SSH-Schlüssel.

## Installation

Kopiere `sync_remote.sh` in dein Projekt, beispielsweise:

```text
my-project/
├── scripts/
│   ├── sync_remote.sh
│   └── deploy.sh
└── dist/
```

In `deploy.sh` kannst du die Funktionen einbinden:

```bash
#!/usr/bin/env bash
set -e

source "$(dirname "${BASH_SOURCE[0]}")/sync_remote.sh"
```

## Konfiguration

Setze folgende Umgebungsvariablen **vor** dem Aufruf:

| Variable                  | Pflicht | Beschreibung                                                                                                          |
| ------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------- |
| `SYNC_REMOTE_HOST`        | Ja      | SSH-Hostname oder IP-Adresse                                                                                          |
| `SYNC_REMOTE_USER`        | Ja      | SSH-Benutzer auf dem Zielserver                                                                                       |
| `SYNC_REMOTE_ROOT`        | Ja      | Absolutes Zielverzeichnis auf dem Server; `/` ist nicht erlaubt                                                       |
| `SYNC_REMOTE_SOURCE_ROOT` | Nein    | Lokales übergeordnetes Verzeichnis für `sync_remote`; standardmäßig zwei Ebenen oberhalb von `sync_remote.sh`         |
| `SYNC_REMOTE_TOUCH_FILE`  | Nein    | Relativer Pfad zu einer Datei, deren Änderungszeit nach erfolgreichem `sync_remote` mittels `touch` aktualisiert wird |

Beispiel:

```bash
export SYNC_REMOTE_HOST="example.com"
export SYNC_REMOTE_USER="deploy"
export SYNC_REMOTE_ROOT="/var/www/sites"
export SYNC_REMOTE_SOURCE_ROOT="$HOME/projects"
# Optional: Das übergeordnete Verzeichnis muss bereits existieren.
export SYNC_REMOTE_TOUCH_FILE="website/public/deploy-success.txt"
```

Für Remote-Pfade sind bewusst nur Buchstaben, Ziffern, Punkte, Unterstriche, Bindestriche und Schrägstriche zugelassen. Pfadkomponenten `.` und `..` sind unzulässig. Remote-Pfade mit Leerzeichen werden nicht unterstützt.

## Verwendung

### 1. Projektverzeichnis synchronisieren

```bash
sync_remote "website"
```

Mit obiger Konfiguration wird Folgendes synchronisiert:

```text
$HOME/projects/website/  ->  deploy@example.com:/var/www/sites/website/
```

Bestimmte Dateien oder Verzeichnisse ausschließen:

```bash
sync_remote "website" ".git/" "node_modules/" "*.log"
```

Vorher nur eine Vorschau anzeigen:

```bash
sync_remote --dry-run "website" ".git/" "node_modules/"
```

Der Helper kann nach `chmod +x sync_remote.sh` auch direkt ausgeführt werden:

```bash
./sync_remote.sh --dry-run website
./sync_remote.sh website
```

### 2. Vorschau für ein beliebiges Verzeichnis

```bash
sync_remote_preview "./dist" "website/public" "*.map"
```

Zeigt, was `rsync` verändern würde, **ohne Dateien hochzuladen oder zu löschen**. Für die Vorschau muss das Zielverzeichnis bzw. ein geeignetes übergeordnetes Verzeichnis möglicherweise bereits existieren.

### 3. Beliebiges Verzeichnis tatsächlich synchronisieren

```bash
sync_remote_directory "./dist" "website/public" "*.map"
```

Legt bei Bedarf das Zielverzeichnis an und führt anschließend die Synchronisierung durch.

### 4. Einzelne Datei hochladen

```bash
upload_remote_file "./config/app.json" "website/config/app.json"
```

Das Zielverzeichnis wird bei Bedarf erstellt. Eine bereits vorhandene Zieldatei kann überschrieben werden.

## Beispiel: Deployment-Skript

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/sync_remote.sh"

export SYNC_REMOTE_HOST="example.com"
export SYNC_REMOTE_USER="deploy"
export SYNC_REMOTE_ROOT="/var/www/sites"
export SYNC_REMOTE_SOURCE_ROOT="$HOME/projects"

sync_remote --dry-run "website" ".git/" "node_modules/"

# Erst nach Kontrolle der Vorschau den echten Aufruf aktivieren:
# sync_remote "website" ".git/" "node_modules/"
```

## ⚠️ Wichtig: Löschverhalten und Sicherheit

- `sync_remote` und `sync_remote_directory` verwenden **`rsync --delete`**. Dateien, die nur auf dem Server vorhanden sind, **werden gelöscht**, sofern sie nicht durch passende rsync-Ausschlussregeln geschützt sind. Kontrolliere vor dem echten Deployment die Vorschau und beide Verzeichnispfade.
- `sync_remote_preview` und `sync_remote --dry-run` **verändern keine Remote-Dateien**.
- Ausschlussmuster folgen den rsync-Regeln. Sie ersetzen keine sorgfältige Prüfung des Zielverzeichnisses.
- Das Skript bietet keine Datensicherung und keine Wiederherstellungsfunktion.
- Speichere keine Passwörter oder privaten SSH-Schlüssel im Repository. Beschränke die Rechte des Deployment-Benutzers auf die benötigten Verzeichnisse.
- `SYNC_REMOTE_TOUCH_FILE` wird **nur** nach einem erfolgreichen echten Aufruf von `sync_remote` aktualisiert. Das übergeordnete Verzeichnis muss bereits vorhanden sein.
- Lokale Pfade dürfen Leerzeichen enthalten, Remote-Pfade bewusst nicht.

## Rückgabecodes

Alle Funktionen liefern bei Erfolg `0`, bei Fehlern einen Wert ungleich `0`. Fehlercodes von `rsync` werden nach Möglichkeit unverändert weitergegeben.

```bash
if ! upload_remote_file "./build/index.html" "website/index.html"; then
    echo "Deployment failed" >&2
    exit 1
fi
```

## Lizenz und Autor

Copyright © 2026 **Roman Drechsel** — [roman-drechsel.de](https://roman-drechsel.de).

Dieses Projekt ist unter der **GNU General Public License v3.0 (GPL-3.0-only)** lizenziert.

Du darfst diese Software gemäß den Bedingungen der GNU GPL v3.0 kostenlos verwenden, verändern und weiterverbreiten – auch für kommerzielle Zwecke.

Den vollständigen Lizenztext findest du in der Datei [`LICENSE`](LICENSE) oder auf der [GNU-Webseite zur GPL v3.0](https://www.gnu.org/licenses/gpl-3.0.de.html).

## KI-unterstützte Entwicklung

Diese Skripte und ihre Dokumentation wurden teilweise mit Unterstützung künstlicher Intelligenz (KI), unter anderem ChatGPT, erstellt. KI-unterstützter Code ist keine Garantie für Fehlerfreiheit. Prüfe und teste die Skripte für deinen eigenen Anwendungsfall, insbesondere bevor du dich auf automatisierte Sicherungen oder Wiederherstellungen verlässt.
