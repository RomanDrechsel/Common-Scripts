# Betterbird & Thunderbird – Sicherung der Einstellungen

[🇬🇧 English](README.md) | **🇩🇪 Deutsch**

Bash-Skripte zum Exportieren und Wiederherstellen der Profileinstellungen von Betterbird und Thunderbird unter Linux, ohne die eigentlichen E-Mails zu sichern. Eine optionale Sitzungsverwaltung beendet den laufenden Mailclient vor dem Export und startet ihn anschließend erneut.

Geeignet für native und Flatpak-Installationen, manuelle Sicherungen und die Integration in bestehende Backup-Skripte.

## Funktionen

- Ausgewählte Profileinstellungen in ein ZIP-Archiv exportieren.
- Einstellungen in einem neuen oder leeren Profilverzeichnis wiederherstellen.
- Betterbird und Thunderbird einschließlich Flatpak-Installationen unterstützen.
- Laufenden Mailclient optional erkennen, beenden und erneut starten.
- Kein Neustart, wenn der Mailclient vor der Sicherung nicht lief.
- ZIP-Archiv vor dem Ersetzen einer bestehenden Sicherung überprüfen.
- Export verweigern, wenn ein passender laufender Mailclient erkannt wird.
- Dateiberechtigungen des Sicherungsarchivs auf `600` beschränken.

## Skripte

| Skript | Aufgabe |
| --- | --- |
| `betterbird-backup.sh` | Export und Import von Profileinstellungen. Kann direkt ausgeführt oder aus einem anderen Bash-Skript eingebunden werden. |
| `mailclient-session-backup.sh` | Mailclient vor dem Export erkennen und beenden sowie anschließend erneut starten. Muss gemeinsam mit `betterbird-backup.sh` eingebunden werden. |

Die Sitzungsverwaltung ist optional, wenn du den Mailclient vor dem Export oder Import manuell schließt.

## Unterstützte Installationen

| Mailclient | Nativ | Flatpak |
| --- | --- | --- |
| Betterbird | Unterstützung implementiert | Unterstützung implementiert |
| Thunderbird | Unterstützung implementiert | Unterstützung implementiert |

Die Sitzungsverwaltung erkennt die Flatpak-Anwendungs-IDs `eu.betterbird.Betterbird` und `org.mozilla.Thunderbird`. Der Export arbeitet mit dem angegebenen Profilverzeichnis und ist nicht an eine bestimmte Installationsart gebunden.

Diese Kombinationen sind in den Skripten implementiert. Das bedeutet nicht, dass jede Programmversion oder Installation getestet wurde.

## Voraussetzungen

- Linux mit Zugriff auf `/proc`
- Bash ab Version 4 (keine POSIX-`sh`)
- `zip`, `unzip`, `find`, `pgrep` und die üblichen GNU Coreutils (einschließlich `realpath`, `mktemp`, `stat`, `readlink`, `chmod` und `mv`)
- `id` sowie bei Ausführung als root für einen anderen Benutzer `runuser`
- `flatpak` für die Sitzungsverwaltung von Flatpak-Anwendungen
- Eine erreichbare grafische Benutzersitzung für den automatischen Neustart

Unter Arch Linux / Manjaro:

```bash
sudo pacman -S --needed bash zip unzip findutils procps-ng coreutils util-linux
```

Für Flatpak-Installationen muss zusätzlich `flatpak` installiert sein.

## Installation

Lege beide Skripte im selben Verzeichnis ab. Mache das Exportskript ausführbar, wenn du es direkt starten möchtest:

```bash
chmod +x betterbird-backup.sh
```

Eine zusätzliche Installation oder Konfigurationsdatei ist nicht erforderlich.

## Profilverzeichnis ermitteln

Öffne in Betterbird oder Thunderbird **Hilfe → Informationen zur Fehlerbehebung** und suche nach **Profilordner** (die Bezeichnung kann je nach Version und Sprache variieren). Verwende das tatsächliche Profilverzeichnis, das die Datei `prefs.js` enthält, nicht dessen übergeordnetes Verzeichnis.

Typische Speicherorte unter Linux:

| Installation | Üblicher Profilpfad |
| --- | --- |
| Betterbird / Thunderbird (nativ) | `~/.thunderbird/<profile>` |
| Betterbird (Flatpak) | `~/.var/app/eu.betterbird.Betterbird/.thunderbird/<profile>` |
| Thunderbird (Flatpak) | `~/.var/app/org.mozilla.Thunderbird/.thunderbird/<profile>` |

Die Speicherorte können abweichen. Überprüfe stets den tatsächlichen Profilpfad. Native Installationen von Betterbird und Thunderbird können dasselbe übergeordnete Profilverzeichnis verwenden. Der Pfad allein lässt daher nicht unbedingt auf den Mailclient schließen.

## Verwendung

Alle Pfade in den folgenden Beispielen sind Platzhalter. Ersetze sie durch deine tatsächlichen Pfade.

### Einstellungen manuell exportieren

Schließe zunächst den Mailclient und führe anschließend Folgendes aus:

```bash
./betterbird-backup.sh export \
    "$HOME/backups/mail-settings.zip" \
    "$HOME/.thunderbird/xxxxxxxx.default-release"
```

Syntax:

```text
betterbird-backup.sh export <archive.zip> <profile>
```

Das Archiv muss außerhalb des Profilverzeichnisses liegen. Fehlende übergeordnete Verzeichnisse des Archivs werden automatisch erstellt. Ein vorhandenes Archiv wird erst nach erfolgreicher Überprüfung des neuen Archivs ersetzt.

### Export mit automatischem Beenden und Neustarten

Binde beide Skripte in einer Bash-Shell oder einem aufrufenden Skript ein:

```bash
#!/usr/bin/env bash

source "/path/to/betterbird-backup.sh"
source "/path/to/mailclient-session-backup.sh"

mailclient_backup_with_restart \
    auto \
    "$USER" \
    "$HOME/backups/mail-settings.zip" \
    "$HOME/.thunderbird/xxxxxxxx.default-release" \
    auto
```

Syntax:

```text
mailclient_backup_with_restart <client> <user> <archive> <profile> [mode]
```

| Argument | Beschreibung |
| --- | --- |
| `client` | `auto`, `betterbird` oder `thunderbird` |
| `user` | Linux-Benutzerkonto, unter dem der Mailclient läuft |
| `archive` | Ziel-ZIP-Archiv |
| `profile` | Profilverzeichnis mit `prefs.js` |
| `mode` | `auto`, `flatpak` oder `native` (Standard: `auto`) |

Bei einem nicht verwendeten nativen Profil muss `betterbird` oder `thunderbird` ausdrücklich angegeben werden, da der Mailclient nicht allein anhand des Pfades ermittelt werden kann.

Beispiele (nach Einbinden beider Skripte):

```bash
# Native Betterbird
mailclient_backup_with_restart betterbird "$USER" \
    "$HOME/backups/betterbird.zip" \
    "$HOME/.thunderbird/xxxxxxxx.default-release" native

# Flatpak Thunderbird
mailclient_backup_with_restart thunderbird "$USER" \
    "$HOME/backups/thunderbird.zip" \
    "$HOME/.var/app/org.mozilla.Thunderbird/.thunderbird/xxxxxxxx.default-release" flatpak
```

Die Sitzungsverwaltung versucht:

1. Einen passenden Mailclient-Prozess und dessen Installationsart zu ermitteln.
2. Die Umgebungsvariablen seiner grafischen Sitzung zu erfassen.
3. `SIGTERM` zu senden und auf das Beenden des Mailclients zu warten.
4. Die Einstellungen zu exportieren und das Archiv zu überprüfen.
5. Den Mailclient erneut zu starten, sofern die Sitzungsverwaltung ihn zuvor beendet hat – auch wenn der Export fehlgeschlagen ist.

Wenn kein passender Mailclient läuft, wird die Sicherung durchgeführt, ohne ihn anschließend zu starten. Werden mehrere mögliche Instanzen erkannt, kann das Skript abbrechen, statt willkürlich eine auszuwählen.

> [!WARNING]
> Speichere Entwürfe und beende laufende E-Mail-Vorgänge vor einer automatisierten Sicherung. Die Sitzungsverwaltung verwendet `SIGTERM` anstelle der normalen Beenden-Funktion der Anwendung. Falls ein Flatpak-Mailclient nicht beendet wird, kann ersatzweise `flatpak kill` verwendet werden, wodurch ungespeicherte Änderungen verloren gehen können.

### Einstellungen wiederherstellen

Schließe den Mailclient vor der Wiederherstellung manuell:

```bash
./betterbird-backup.sh import \
    "$HOME/backups/mail-settings.zip" \
    "$HOME/.thunderbird/restored-profile"
```

Syntax:

```text
betterbird-backup.sh import <archive.zip> <new-empty-profile>
```

Das Ziel darf noch nicht existieren oder muss ein leeres Verzeichnis sein. Das übergeordnete Verzeichnis muss bereits existieren. Vorhandene, nicht leere Profile werden niemals überschrieben oder zusammengeführt.

Der Import überprüft die Integrität des Archivs und die Kennzeichnung des Sicherungsformats, entpackt die Daten in ein temporäres Verzeichnis und prüft, ob `prefs.js` vorhanden ist, bevor das wiederhergestellte Profil an seinen Zielort verschoben wird.

Wähle oder registriere das wiederhergestellte Verzeichnis anschließend über die Profilverwaltung des Mailclients. Das Skript aktualisiert `profiles.ini` nicht und startet das wiederhergestellte Profil nicht automatisch. Überprüfe vor der Verwendung die Kontopfade und Einstellungen, insbesondere bei einem Wechsel zwischen Installationen.

### Exportskript als Bash-Bibliothek verwenden

```bash
source "/path/to/betterbird-backup.sh"

betterbird_export_settings "$archive" "$profile"
betterbird_import_settings "$archive" "$new_profile"
```

Die Variablen in diesem Beispiel müssen vorher gesetzt werden. Beide Funktionen überprüfen auch selbst, ob ein Mailclient läuft.

## Was wird gesichert?

Das Exportskript verwendet eine ausgewählte Liste von Profildateien und -verzeichnissen, darunter die folgenden, sofern vorhanden:

| Kategorie | Beispiele |
| --- | --- |
| Einstellungen und Konten | `prefs.js`, `user.js` |
| Gespeicherte Zugangsdaten und Zertifikate | `logins.json`, `key4.db`, `cert9.db`, `pkcs11.txt` |
| Adressbücher und Datenbanken | SQLite-Datenbanken auf oberster Profilebene und zugehörige WAL-/SHM-Dateien, ältere Adressbücher |
| Kalender | `calendar-data` |
| Erweiterungen und Anpassungen | `extensions`, `chrome`, `storage`, Erweiterungskonfiguration |
| OpenPGP | `openpgp.sqlite`, Schlüsselbunddateien und Datei mit verschlüsselter Passphrase |
| Benutzeroberfläche und Sitzungsstatus | `session.json`, `xulstore.json`, Ordnerkonfiguration |
| Nachrichtenfilter und POP3-Status | `msgFilterRules.dat`, `popstate.dat` unter `ImapMail`, `Mail` und `News` |

### Was wird nicht gesichert?

- Reguläre Nachrichtenspeicher unter `ImapMail`, `Mail` und `News`
- Lokale Ordner und lokal gespeicherte E-Mails
- Nachrichtenindexdateien (`*.msf`)
- Die neu erstellbare globale Nachrichtensuchdatenbank
- Cache- und Maildir-Nachrichtenpfade, die durch die Ausschlussmuster des ZIP-Befehls erfasst werden
- Dateien zur Profilregistrierung außerhalb des ausgewählten Profilverzeichnisses, beispielsweise `profiles.ini`

> [!IMPORTANT]
> Dies ist eine **Sicherung der Einstellungen**, keine vollständige E-Mail- oder Profilsicherung. Sichere lokale Ordner, POP3-Nachrichten und andere unersetzliche Daten separat. Der POP3-Downloadstatus wird gesichert, obwohl heruntergeladene Nachrichten nicht enthalten sind. Das Wiederherstellen dieses Status stellt diese Nachrichten nicht wieder her. Ausgewählte Datenbanken und Erweiterungsspeicher können dennoch nachrichtenbezogene oder andere sensible Daten enthalten.

## Sicherheit und Einschränkungen

- Archive enthalten möglicherweise sensible Zugangsdaten, Schlüssel und persönliche Daten. Sie werden durch die Skripte nicht verschlüsselt. Bewahre sie sicher auf und verwende zur Wiederherstellung ausschließlich vertrauenswürdige Archive.
- Die Prozesserkennung basiert auf Linux-Prozessinformationen, Kommandozeilenargumenten und Flatpak-Instanzinformationen. Ungewöhnliche Programmstarter, individuelle Profilpfade oder mehrere Instanzen können Probleme bei der Erkennung oder beim Neustart verursachen.
- Die Sitzungsverwaltung garantiert keine eindeutige Profilzuordnung, wenn der laufende Mailclient ohne ausdrückliches `-profile`-Argument gestartet wurde. Vermeide während automatisierter Sicherungen gleichzeitig laufende Mailclients oder Profile.
- Der automatische Neustart erfordert eine erreichbare Benutzersitzung und einen D-Bus-Socket. Die Ausführung über cron, systemd oder als root kann eine zusätzliche Sitzungskonfiguration erfordern. Bei als root erstellten Archiven muss möglicherweise auch der Dateieigentümer angepasst werden.
- Beim Neustart werden ausgewählte Umgebungsvariablen der grafischen Sitzung und ein erkanntes explizites Profilargument wiederverwendet, jedoch nicht zwingend sämtliche ursprünglichen Kommandozeilenargumente.
- Sicherungen sind für kompatible Programmversionen vorgesehen. Eine Wiederherstellung über Versions- oder Mailclient-Grenzen hinweg ist nicht garantiert. Absolute Pfade und nicht unterstützte Einstellungen können manuelle Anpassungen erfordern.
- Zeitplanung, Verschlüsselung und Backup-Rotation sind nicht enthalten. Integriere die Funktionen bei Bedarf in deinen eigenen Backup-Ablauf.
- Die Überprüfung laufender Prozesse stellt keine exklusive Profilsperre dar. Starte den Mailclient während eines Exports oder Imports nicht.

## Rückgabewerte

| Code | Bedeutung |
| --- | --- |
| `0` | Der angeforderte Vorgang wurde erfolgreich abgeschlossen. |
| `1` | Ein Vorgang ist fehlgeschlagen, beispielsweise die Überprüfung, Prozesserkennung, das Beenden oder der Neustart. |
| `2` | Ungültige Argumente oder fehlerhafter Aufruf. |

Wenn sowohl der Export als auch der Neustart fehlschlagen, gibt die Sitzungsverwaltung den Fehlercode des Exports vorrangig zurück. Ein fehlgeschlagener Neustart kann daher auch dann gemeldet werden, wenn das Sicherungsarchiv erfolgreich erstellt wurde.

## KI-unterstützte Entwicklung

Diese Skripte und ihre Dokumentation wurden teilweise mit Unterstützung künstlicher Intelligenz (KI), unter anderem ChatGPT, erstellt. KI-unterstützter Code ist keine Garantie für Fehlerfreiheit. Prüfe und teste die Skripte für deinen eigenen Anwendungsfall, insbesondere bevor du dich auf automatisierte Sicherungen oder Wiederherstellungen verlässt.
