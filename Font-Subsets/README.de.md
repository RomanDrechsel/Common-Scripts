# Font-Subset-Generator

[🇬🇧 English](README.md) | **🇩🇪 Deutsch**

Ein Python-Skript, das alle Dateien eines Verzeichnisses rekursiv durchsucht, die darin verwendeten Unicode-Codepoints sammelt und aus einer TTF- oder OTF-Schriftdatei eine reduzierte WOFF2-, WOFF-, TTF- oder OTF-Schrift erstellt. Geeignet für Webseiten, statische Texte, Quellcode-Darstellungen und andere Anwendungen mit bekanntem Zeichenvorrat.

## Funktionen

- Alle Dateien einschließlich verschachtelter Unterverzeichnisse rekursiv durchsuchen.
- Eindeutige Unicode-Codepoints sammeln und druckbare ASCII-Zeichen, Tabulator, Zeilenvorschub und Wagenrücklauf immer berücksichtigen.
- UTF-8, UTF-8 mit BOM, UTF-16 und Windows-1252 beim Lesen ausprobieren.
- WOFF2-, WOFF-, TTF- oder OTF-Schriften mithilfe von FontTools erstellen.
- Zwischen standardmäßiger und aggressiver kompakter Reduzierung wählen.
- Fehlende Ausgabeverzeichnisse automatisch erstellen.
- Zeichenanzahl pro Datei, Gesamtzahl der Codepoints, Schriftdateigrößen und prozentuale Reduzierung ausgeben.

## Voraussetzungen und Installation

- Python 3.10 oder neuer (empfohlen)
- FontTools (Brotli nur für WOFF2-Ausgabe erforderlich)

Installiere die Abhängigkeiten in einer virtuellen Umgebung:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install 'fonttools[woff]'
```

Alternativ unter Arch Linux oder Manjaro:

```bash
sudo pacman -S python-fonttools python-brotli
```

## Verwendung

```bash
python3 create_font_subset.py [--compact] <scan> <font> <output>
```

| Argument       | Beschreibung                                                                |
| -------------- | --------------------------------------------------------------------------- |
| `scan`         | Erforderliches Verzeichnis, das rekursiv durchsucht wird.                   |
| `font`         | Erforderlicher Pfad zur TTF- oder OTF-Quelldatei.                           |
| `output`       | Erforderlicher Ausgabepfad; verwende `.woff2`, `.woff`, `.ttf` oder `.otf`. |
| `--compact`    | Optionale aggressive Reduzierung der Schriftdaten.                          |
| `-h`, `--help` | Kommandozeilenhilfe anzeigen.                                               |

Relative Pfade beziehen sich auf das aktuelle Arbeitsverzeichnis. Alle drei Positionsargumente sind erforderlich.

### Ausgabeformate

Die Dateiendung bestimmt automatisch das Ausgabeformat (unabhängig von Groß- und Kleinschreibung).

| Endung   | Unterstützte Konturen der Quellschrift |
| -------- | -------------------------------------- |
| `.woff2` | TrueType oder CFF; benötigt Brotli     |
| `.woff`  | TrueType oder CFF                      |
| `.ttf`   | TrueType                               |
| `.otf`   | CFF oder CFF2                          |

Das Subsetting konvertiert keine Konturtechnologien. Nicht unterstützte Endungen und inkompatible TTF-/OTF-Ausgaben werden abgelehnt. Die Quellschrift kann nicht überschrieben werden.

```bash
python3 create_font_subset.py ./sourcecode ./fonts/JetBrainsMono.ttf ./fonts/subset.woff
python3 create_font_subset.py ./sourcecode ./fonts/JetBrainsMono.ttf ./fonts/subset.ttf
python3 create_font_subset.py ./sourcecode ./fonts/SourceCodePro-Regular.otf ./fonts/subset.otf
```

### Standardmodus

```bash
python3 create_font_subset.py ./sourcecode ./fonts/JetBrainsMono.ttf ./public/fonts/JetBrainsMono-subset.woff2
```

### Kompaktmodus

```bash
python3 create_font_subset.py --compact ./sourcecode ./fonts/JetBrainsMono.ttf ./public/fonts/JetBrainsMono-subset.woff2
```

## Reduzierungsmodi

| Funktion                                  | Standard                                 | Kompakt                              |
| ----------------------------------------- | ---------------------------------------- | ------------------------------------ |
| Zeichenreduzierung                        | Ja                                       | Ja                                   |
| Namensmetadaten                           | Alle Namens-IDs und Sprachen angefordert | Wesentliche Namens-IDs, nur Englisch |
| OpenType-Layoutfunktionen                 | Alle Funktionen angefordert              | Entfernt                             |
| Hinting                                   | FontTools-Standardverhalten              | Entfernt                             |
| Legacy-Kerning, Symbol-cmap, Glyphennamen | FontTools-Standardverhalten              | Deaktiviert                          |
| Entfernung zusätzlicher Tabellen          | FontTools-Standardverhalten              | Unter anderem GDEF, GPOS und GSUB    |

Der Standardmodus ist die sicherere Wahl für allgemeine Texte. Der Kompaktmodus zielt auf kleine Dateigrößen ab, insbesondere bei einfachen statischen Texten oder Quellcode-Darstellungen. Er kann Ligaturen, Kerning, Zeichenpositionierung, die Formung komplexer Schriftsysteme und die Darstellung bei kleinen Schriftgrößen beeinträchtigen.

## Erstellte Schrift auf einer Webseite verwenden

```css
@font-face {
    font-family: "Code Subset";
    src: url("/fonts/JetBrainsMono-subset.woff2") format("woff2");
    font-display: swap;
}

.source-code {
    font-family: "Code Subset", monospace;
}
```

Passe die URL und Schriftattribute an deine tatsächliche Schrift und Bereitstellung an.

## Einschränkungen und Empfehlungen

- Das Skript durchsucht alle Dateien ohne Dateiendungsfilter oder Verzeichnisausschlüsse. Verwende ein separates Eingabeverzeichnis mit Textdateien; Binärdateien können als Text dekodiert werden und unerwünschte Zeichen hinzufügen.
- Nicht dekodierbare oder nicht lesbare Dateien werden übersprungen. Prüfe die Konsolenausgabe auf übersprungene Dateien.
- Die Kodierungsversuche sind heuristisch und keine automatische Zeichensatz-Erkennung.
- Nur Zeichen, die in der Quellschrift vorhanden sind, können übernommen werden. Die Anzahl gesammelter Unicode-Codepoints entspricht nicht zwangsläufig der Anzahl ausgegebener Glyphen.
- Erstelle das Subset erneut, wenn sich die Eingabetexte ändern, da neue Zeichen sonst fehlen können.
- Lege Quellschriften und erzeugte Dateien außerhalb des Scan-Verzeichnisses ab. Die Quellschrift ist vor Überschreiben geschützt, andere bestehende Ausgabedateien können jedoch überschrieben werden.
- Die Größenreduzierung hängt von der Schrift und den gesammelten Zeichen ab. Eine kleinere Datei ist nicht garantiert.
- Prüfe vor dem Verändern, Einbetten oder Weitergeben die Lizenz der Quellschrift. Der Kompaktmodus entfernt Metadaten, die Lizenzinformationen enthalten können; bewahre erforderliche Hinweise separat auf.

## Lizenz und Autor

Copyright © 2026 **Roman Drechsel** — [roman-drechsel.de](https://roman-drechsel.de).

Dieses Projekt ist unter der **GNU General Public License v3.0 (GPL-3.0-only)** lizenziert.

Du darfst diese Software gemäß den Bedingungen der GNU GPL v3.0 kostenlos verwenden, verändern und weiterverbreiten – auch für kommerzielle Zwecke.

Den vollständigen Lizenztext findest du in der Datei [`LICENSE`](LICENSE) oder auf der [GNU-Webseite zur GPL v3.0](https://www.gnu.org/licenses/gpl-3.0.de.html).

## KI-unterstützte Entwicklung

Dieses Skript und seine Dokumentation wurden teilweise mit Unterstützung künstlicher Intelligenz (KI), unter anderem ChatGPT, erstellt. KI-unterstützter Code ist keine Garantie für Fehlerfreiheit. Prüfe und teste das Skript für deinen eigenen Anwendungsfall.
