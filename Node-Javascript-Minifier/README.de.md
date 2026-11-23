# JavaScript Minifier

[🇬🇧 English](README.md) | **🇩🇪 Deutsch**

Ein universell einsetzbares Node.js-Kommandozeilenprogramm zum rekursiven Minifizieren von JavaScript-Dateien mit **esbuild**. Es erzeugt aus `.js`-Dateien jeweils `.min.js`-Dateien und übernimmt dabei die relative Ordnerstruktur. Quell- und Zielverzeichnisse werden als Parameter angegeben – **ohne fest eingetragene Projektpfade**.

## Funktionen

- Rekursive Verarbeitung von `.js`-Dateien im Quellverzeichnis.
- Bereits minifizierte `.min.js`-Dateien sowie die Verzeichnisse `.git` und `node_modules` überspringen.
- Unterordner im Zielverzeichnis beibehalten.
- Minifizieren **ohne Bundling** (`bundle: false`), wie im ursprünglichen Skript.
- Standardmäßig **ES2017** als JavaScript-Zielversion verwenden; mit `--target` anpassbar.
- Optional veraltete Ausgabedateien mit `--clean` anhand einer Manifestdatei bereinigen.
- Fortschritt ausgeben und bei Fehlern einen Exit-Code ungleich null zurückgeben.

## Voraussetzungen

- Node.js ab Version 18
- npm

## Installation

Kopiere `javascript-minifier.mjs` und `package.json` in dasselbe Verzeichnis und installiere die Abhängigkeiten:

```bash
npm install
```

## Verwendung

Du kannst das Skript aus einem beliebigen Arbeitsverzeichnis aufrufen:

```bash
node /pfad/zu/javascript-minifier.mjs --src ./assets/javascript --dest ./public/js
```

Alternativ mit zwei Positionsargumenten:

```bash
node /pfad/zu/javascript-minifier.mjs ./assets/javascript ./public/js
```

**Relative Pfade beziehen sich auf das aktuelle Arbeitsverzeichnis**, nicht auf das Verzeichnis des Skripts. Absolute Pfade sind ebenfalls möglich.

### Parameter

| Parameter              | Beschreibung                                                             |
| ---------------------- | ------------------------------------------------------------------------ |
| `--src <verzeichnis>`  | Erforderliches Quellverzeichnis.                                         |
| `--dest <verzeichnis>` | Erforderliches Zielverzeichnis (wird bei Bedarf erstellt).               |
| `--target <version>`   | JavaScript-Zielversion für esbuild (Standard: `es2017`, z. B. `es2020`). |
| `--clean`              | Veraltete, zuvor vom Tool erfasste Dateien entfernen.                    |
| `-h`, `--help`         | Hilfe anzeigen.                                                          |

Verwende entweder **beide benannten Parameter** (`--src`, `--dest`) oder **zwei Positionsargumente**. Eine Mischung ist nicht erlaubt.

### Beispiel

Quellverzeichnis:

```text
assets/javascript/
├── main.js
├── main.min.js
└── admin/
    └── dashboard.js
```

Befehl:

```bash
node javascript-minifier.mjs --src assets/javascript --dest public/js
```

Erzeugte Dateien:

```text
public/js/
├── .javascript-minifier-manifest.json
├── main.min.js
└── admin/
    └── dashboard.min.js
```

Die schon vorhandene Quelldatei `main.min.js` wird nicht erneut minifiziert.

## Bereinigung und Sicherheit

Standardmäßig **löscht das Programm keine Dateien**. Stattdessen merkt es sich die generierten Ausgaben in der Datei `.javascript-minifier-manifest.json` im Zielverzeichnis. Falls eine Quelldatei entfernt wurde, kannst du die dazugehörige alte Ausgabe gezielt bereinigen:

```bash
node javascript-minifier.mjs --src assets/javascript --dest public/js --clean
```

`--clean` löscht nur Dateien, deren Pfade zuvor im Manifest erfasst wurden und die beim aktuellen Lauf nicht mehr erzeugt werden. **Achtung:** Wurde eine solche Datei zwischenzeitlich durch eine andere Datei unter demselben Pfad ersetzt, kann das Tool deren Herkunft nicht erkennen. Verwende deshalb ein eigenes Zielverzeichnis und bearbeite generierte Dateien nicht manuell. Gleichnamige Ausgaben werden auch ohne `--clean` überschrieben.

Das Zielverzeichnis muss außerhalb des Quellverzeichnisses liegen. Symbolische Links auf Verzeichnisse werden nicht verfolgt.

## Hinweise

- Es werden nur `.js`-Dateien verarbeitet (keine `.mjs`-, `.cjs`- oder TypeScript-Dateien).
- Es findet **kein Bundling** statt; Source Maps werden nicht erzeugt.
- Node.js und das Paket `esbuild` sind erforderlich. Es handelt sich nicht um eine native ausführbare Standalone-Datei.
- Ein Watch-Modus ist nicht enthalten.

## Lizenz und Autor

Copyright © 2026 **Roman Drechsel** — [roman-drechsel.de](https://roman-drechsel.de).

Dieses Projekt ist unter der **GNU General Public License v3.0 (GPL-3.0-only)** lizenziert.

Du darfst diese Software gemäß den Bedingungen der GNU GPL v3.0 kostenlos verwenden, verändern und weiterverbreiten – auch für kommerzielle Zwecke.

Den vollständigen Lizenztext findest du in der Datei [`LICENSE`](LICENSE) oder auf der [GNU-Webseite zur GPL v3.0](https://www.gnu.org/licenses/gpl-3.0.de.html).

## KI-unterstützte Entwicklung

Diese Skripte und ihre Dokumentation wurden teilweise mit Unterstützung künstlicher Intelligenz (KI), unter anderem ChatGPT, erstellt. KI-unterstützter Code ist keine Garantie für Fehlerfreiheit. Prüfe und teste die Skripte für deinen eigenen Anwendungsfall, insbesondere bevor du dich auf automatisierte Sicherungen oder Wiederherstellungen verlässt.
