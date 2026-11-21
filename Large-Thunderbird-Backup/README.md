# Betterbird & Thunderbird Settings Backup

**🇬🇧 English** | [🇩🇪 Deutsch](README.de.md)

Bash scripts for exporting and restoring Betterbird and Thunderbird profile settings on Linux, without backing up the actual mail messages. An optional session manager stops the running mail client before exporting and restarts it afterwards.

Suitable for native and Flatpak installations, manual backups and integration into existing backup scripts.

## Features

- Export selected profile settings to a ZIP archive.
- Restore settings into a new or empty profile directory.
- Support Betterbird and Thunderbird, including Flatpak installations.
- Optionally detect, stop and restart a running mail client.
- Skip restarting the client if it was not running before the backup.
- Verify the ZIP archive before replacing an existing backup.
- Refuse to export a profile when a matching running mail client is detected.
- Restrict backup archive permissions to `600`.

## Scripts

| Script | Purpose |
| --- | --- |
| `betterbird-backup.sh` | Export and import profile settings. Can be executed directly or sourced from another Bash script. |
| `mailclient-session-backup.sh` | Detect, stop and restart the mail client around an export. Must be sourced together with `betterbird-backup.sh`. |

The session manager is optional if you close the mail client manually before exporting or importing settings.

## Supported installations

| Mail client | Native | Flatpak |
| --- | --- | --- |
| Betterbird | Supported by design | Supported by design |
| Thunderbird | Supported by design | Supported by design |

The session manager recognizes the Flatpak application IDs `eu.betterbird.Betterbird` and `org.mozilla.Thunderbird`. The exporter operates on a supplied profile directory rather than a specific installation type.

These combinations are implemented in the scripts; this does not imply that every client version or installation has been tested.

## Requirements

- Linux with access to `/proc`
- Bash 4 or newer (not POSIX `sh`)
- `zip`, `unzip`, `find`, `pgrep` and standard GNU coreutils (including `realpath`, `mktemp`, `stat`, `readlink`, `chmod` and `mv`)
- `id` and, for execution as root on behalf of another user, `runuser`
- `flatpak` for Flatpak session management
- An accessible graphical user session for automatic restart

On Arch Linux / Manjaro:

```bash
sudo pacman -S --needed bash zip unzip findutils procps-ng coreutils util-linux
```

For Flatpak installations, ensure `flatpak` is installed as well.

## Installation

Place both scripts in the same directory. To execute the exporter directly, make it executable:

```bash
chmod +x betterbird-backup.sh
```

No additional installation or configuration file is required.

## Finding your profile directory

In Betterbird or Thunderbird, open **Help → Troubleshooting Information** and locate **Profile Folder** (the wording may vary with the client version and language). Use the actual profile directory containing `prefs.js`, not its parent directory.

Typical Linux locations include:

| Installation | Common profile location |
| --- | --- |
| Native Betterbird / Thunderbird | `~/.thunderbird/<profile>` |
| Flatpak Betterbird | `~/.var/app/eu.betterbird.Betterbird/.thunderbird/<profile>` |
| Flatpak Thunderbird | `~/.var/app/org.mozilla.Thunderbird/.thunderbird/<profile>` |

Locations may vary. Always verify the actual profile path. Native Betterbird and Thunderbird can use the same profile root, so the path alone does not necessarily identify the client.

## Usage

All paths in the following examples are placeholders. Replace them with your actual paths.

### Export settings manually

Close the mail client first, then run:

```bash
./betterbird-backup.sh export \
    "$HOME/backups/mail-settings.zip" \
    "$HOME/.thunderbird/xxxxxxxx.default-release"
```

Syntax:

```text
betterbird-backup.sh export <archive.zip> <profile>
```

The archive must be outside the profile directory. Missing archive parent directories are created automatically. An existing archive is replaced only after the new archive has been verified.

### Export with automatic stop and restart

Source both scripts in a Bash shell or wrapper script:

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

| Argument | Description |
| --- | --- |
| `client` | `auto`, `betterbird` or `thunderbird` |
| `user` | Linux account running the mail client |
| `archive` | Destination ZIP archive |
| `profile` | Profile directory containing `prefs.js` |
| `mode` | `auto`, `flatpak` or `native` (defaults to `auto`) |

For an unused native profile, specify `betterbird` or `thunderbird` explicitly because the client cannot be inferred from the path alone.

Examples (after sourcing both scripts):

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

The session manager attempts to:

1. Identify a matching mail-client process and installation type.
2. Capture its graphical session environment.
3. Send `SIGTERM` and wait for the client to stop.
4. Export the settings and verify the archive.
5. Restart the client if the session manager stopped it, even if the export failed.

If no matching client is running, the backup proceeds without launching it afterwards. If multiple possible instances are detected, the script may abort rather than choose arbitrarily.

> [!WARNING]
> Save drafts and finish any active mail operations before running an automated backup. The session manager uses `SIGTERM`, not the application's normal Quit command. If a Flatpak client does not stop, it may fall back to `flatpak kill`, which can cause loss of unsaved changes.

### Restore settings

Close the mail client manually before restoring:

```bash
./betterbird-backup.sh import \
    "$HOME/backups/mail-settings.zip" \
    "$HOME/.thunderbird/restored-profile"
```

Syntax:

```text
betterbird-backup.sh import <archive.zip> <new-empty-profile>
```

The destination must not exist or must be an empty directory. Its parent directory must already exist. Existing non-empty profiles are never overwritten or merged.

The importer checks archive integrity and the backup format marker, extracts into a temporary staging directory and verifies that `prefs.js` exists before moving the restored profile into place.

After restoring, select or register the restored directory using the mail client's profile manager. The script does not update `profiles.ini` or automatically launch the restored profile. Review account paths and settings before using it, especially when migrating between installations.

### Use the exporter as a Bash library

```bash
source "/path/to/betterbird-backup.sh"

betterbird_export_settings "$archive" "$profile"
betterbird_import_settings "$archive" "$new_profile"
```

The variables in this example must be set beforehand. Both functions also perform their own running-client checks.

## What is backed up?

The exporter uses a selected list of profile files and directories, including the following when present:

| Category | Examples |
| --- | --- |
| Preferences and accounts | `prefs.js`, `user.js` |
| Saved credentials and certificates | `logins.json`, `key4.db`, `cert9.db`, `pkcs11.txt` |
| Address books and databases | Top-level SQLite databases and associated WAL/SHM files, legacy address books |
| Calendars | `calendar-data` |
| Add-ons and customization | `extensions`, `chrome`, `storage`, extension configuration |
| OpenPGP | `openpgp.sqlite`, keyring files and encrypted passphrase file |
| UI and session state | `session.json`, `xulstore.json`, folder configuration |
| Message filters and POP3 state | `msgFilterRules.dat`, `popstate.dat` under `ImapMail`, `Mail` and `News` |

### What is not backed up?

- Regular message stores under `ImapMail`, `Mail` and `News`
- Local folders and locally stored mail messages
- Mail summary files (`*.msf`)
- The rebuildable global message search database
- Matching cache and Maildir message paths excluded by the ZIP command
- Profile registration files outside the selected profile directory, such as `profiles.ini`

> [!IMPORTANT]
> This is a **settings backup**, not a full mail or profile backup. Back up local folders, POP3 messages and any other irreplaceable data separately. POP3 download state is included even though downloaded messages are not; restoring that state does not recover those messages. Selected databases and add-on storage may still contain message-related or other sensitive data.

## Security and limitations

- Archives contain potentially sensitive credentials, keys and personal data. They are not encrypted by the scripts. Store them securely and use only trusted archives for restoration.
- Process detection is based on Linux process information, command lines and Flatpak instance information. Unusual launchers, custom profile paths or multiple instances can cause detection or restart problems.
- The session manager does not guarantee exact profile identification when the running client was launched without an explicit `-profile` argument. Avoid simultaneous clients or profiles during automated backups.
- Automatic restart requires an accessible user session and D-Bus socket. Running from cron, systemd or as root may require additional session configuration. Root-created archives may also need ownership adjustments.
- Restart restores selected GUI environment variables and an explicit profile argument when detected, not necessarily every original command-line argument.
- Backups are intended for compatible client versions. Cross-version or cross-client restoration is not guaranteed; absolute paths and unsupported settings may require manual adjustment.
- No scheduling, encryption or backup rotation is provided. Integrate the functions into your own backup workflow if needed.
- The running-process checks are not an exclusive profile lock. Do not launch the mail client during export or import.

## Exit status

| Code | Meaning |
| --- | --- |
| `0` | The requested operation completed successfully. |
| `1` | An operation failed, for example verification, process detection, shutdown or restart. |
| `2` | Invalid arguments or usage. |

The session manager returns the export failure status in preference to the restart status if both fail. A restart failure may therefore be reported even though the backup archive was successfully created.

