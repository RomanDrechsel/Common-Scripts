# LESS-Compiler

[🇬🇧 English](README.md) | **🇩🇪 Deutsch**

Ein universell einsetzbares Node.js-Kommandozeilenprogramm zum Kompilieren von LESS-Dateien in normale `.css`- und minimierte `.min.css`-Dateien. Quell- und Zielverzeichnis werden als Argumente übergeben; **es gibt keine fest hinterlegten Projektpfade**.

## Funktionen

- `.less`-Dateien rekursiv verarbeiten und die relative Verzeichnisstruktur beibehalten.
- `.css` und `.min.css` mit Less und clean-css erzeugen.
- LESS-Partials mit führendem `_` standardmäßig nicht einzeln kompilieren (mit `--include-partials` änderbar).
- Minimierung mit `--no-minify` abschalten.
- Veraltete Ausgabedateien optional mit `--clean` bereinigen, beschränkt auf zuvor vom Tool protokollierte Dateien.
- Fortschrittsausgaben und Exit-Code ungleich null bei Fehlern.

## Voraussetzungen und Installation

- Node.js ab Version 18 (ES-Module)
- npm

Kopiere `less-compiler.js` und `package.json` in ein Verzeichnis und installiere dort die Abhängigkeiten:

```bash
npm install
```

In einem vorhandenen Node.js-Projekt kannst du alternativ `less` und `clean-css` installieren und sicherstellen, dass das Skript als ES-Modul läuft (`"type": "module"` in der `package.json`).

## Verwendung

Aus dem Verzeichnis mit dem Skript:

```bash
node less-compiler.js --src ./assets/less --dest ./public/css
```

Oder mit Positionsargumenten:

```bash
node less-compiler.js ./assets/less ./public/css
```

Relative Pfade beziehen sich auf das **aktuelle Arbeitsverzeichnis**, nicht auf den Speicherort des Skripts. Absolute Pfade funktionieren ebenfalls.

### Parameter

| Parameter              | Beschreibung                                                                                      |
| ---------------------- | ------------------------------------------------------------------------------------------------- |
| `--src <verzeichnis>`  | Erforderliches Quellverzeichnis mit LESS-Dateien.                                                 |
| `--dest <verzeichnis>` | Erforderliches Zielverzeichnis; wird bei Bedarf angelegt.                                         |
| `--no-minify`          | Nur `.css`-Dateien erzeugen.                                                                      |
| `--include-partials`   | Auch `.less`-Dateien mit führendem `_` separat kompilieren.                                       |
| `--clean`              | Veraltete, im Manifest verzeichnete Ausgaben löschen; dabei leer gewordene Unterordner entfernen. |
| `-h`, `--help`         | Hilfe anzeigen.                                                                                   |

Verwende entweder beide benannten Pfadparameter oder beide Positionsargumente. Mische die Varianten nicht.

### Beispiel

Eingabe:

```text
assets/less/
├── main.less
├── _colors.less
└── admin/
    └── dashboard.less
```

Aufruf:

```bash
node less-compiler.js --src assets/less --dest public/css
```

Ausgabe:

```text
public/css/
├── .less-compiler-manifest.json
├── main.css
├── main.min.css
└── admin/
    ├── dashboard.css
    └── dashboard.min.css
```

`_colors.less` kann über `@import` eingebunden werden, wird aber standardmäßig nicht als eigene CSS-Datei ausgegeben.

## Bereinigung und Sicherheit

Standardmäßig löscht das Skript **keine bisherigen Ausgabedateien**. Nach erfolgreicher Kompilierung speichert es eine Dateiliste unter `.less-compiler-manifest.json` im Zielverzeichnis. Wenn LESS-Dateien gelöscht werden oder du `--no-minify` verwendest, bleiben alte Ausgaben zunächst erhalten. Eine Bereinigung startest du ausdrücklich mit:

```bash
node less-compiler.js --src assets/less --dest public/css --clean
```

`--clean` entfernt nur veraltete Dateipfade, die in früheren Durchläufen dieses Tools protokolliert wurden. Andere `.css`-Dateien werden nicht pauschal entfernt. **Bearbeite generierte CSS-Dateien nicht manuell:** Beim erneuten Kompilieren werden gleichnamige Ausgaben überschrieben. Ersetzt du eine protokollierte Datei durch eine andere Datei mit demselben Pfad, kann `--clean` diese später ebenfalls löschen. Verwende deshalb möglichst ein eigenes Zielverzeichnis und bewahre das Manifest darin auf.

## Hinweise

- Das Programm benötigt die installierten Pakete `less` und `clean-css`; es ist keine native, ohne Node.js lauffähige Datei.
- Symbolische Links im LESS-Quellbaum werden nicht verfolgt.
- Vorhandene CSS-Dateien mit denselben Namen wie die Ausgaben werden überschrieben.
- Ein Watch-Modus ist nicht enthalten.

## Lizenz und Autor

Copyright © 2026 **Roman Drechsel** — [roman-drechsel.de](https://roman-drechsel.de).

Dieses Projekt ist unter der **GNU General Public License v3.0 (GPL-3.0-only)** lizenziert.

Du darfst diese Software gemäß den Bedingungen der GNU GPL v3.0 kostenlos verwenden, verändern und weiterverbreiten – auch für kommerzielle Zwecke.

Den vollständigen Lizenztext findest du in der Datei [`LICENSE`](LICENSE) oder auf der [GNU-Webseite zur GPL v3.0](https://www.gnu.org/licenses/gpl-3.0.de.html).

## KI-unterstützte Entwicklung

Diese Skripte und ihre Dokumentation wurden teilweise mit Unterstützung künstlicher Intelligenz (KI), unter anderem ChatGPT, erstellt. KI-unterstützter Code ist keine Garantie für Fehlerfreiheit. Prüfe und teste die Skripte für deinen eigenen Anwendungsfall, insbesondere bevor du dich auf automatisierte Sicherungen oder Wiederherstellungen verlässt.
