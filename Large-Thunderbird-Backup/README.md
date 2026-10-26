# Betterbird & Thunderbird Backup (Linux)

A Bash tool for **Betterbird and Thunderbird profile backups and restoration** on Linux. Create complete backups or configuration-only backups, with optional AES-256 encrypted ZIP archives. All commands are non-interactive and suitable for cron when fully configured. Backups can gracefully stop and restart the exact selected running desktop client.

> **Project status:** Bash syntax checked; end-to-end restore testing on real Betterbird/Thunderbird profiles, Linux distributions and packaging formats is still required. Do not use as the only backup of important mail data until independently tested.

## Compatibility

The script relies on common Linux command-line utilities, not distribution-specific packaging commands. It is intended to run on Arch Linux / Manjaro, Debian / Ubuntu / Linux Mint, Fedora, openSUSE and similar Linux distributions **when dependencies are installed**. The following identifies supported profile *layouts* rather than verified end-to-end distro tests.

| Client / installation | Profile container | Detection |
| --- | --- | --- |
| Betterbird native / AppImage | `~/.thunderbird` | Yes |
| Thunderbird native / tarball | `~/.thunderbird` | Yes |
| Betterbird Flatpak | `~/.var/app/eu.betterbird.Betterbird/.thunderbird` | Yes |
| Thunderbird Flatpak | `~/.var/app/org.mozilla.Thunderbird/.thunderbird` | Yes |
| Thunderbird Snap | `~/snap/thunderbird/common/.thunderbird` or `~/snap/thunderbird/current/.thunderbird` | Yes, if present |
| Custom profiles | Custom path | `--source DIR` / `--destination DIR` |
| Windows / macOS | — | Not supported |

**Important:** Native Thunderbird and Betterbird can share the *same* `~/.thunderbird` container; installing both does not create independent native profiles. Flatpak apps granted broader filesystem permissions may use the *native* `~/.thunderbird` folder. Snap paths vary. If more than one container is found, the script refuses automatic selection: use `--source DIR` to select the correct one. `--client` sets *search priority* and, for restore, a default target—it does not detect which application currently uses a profile.

### Requirements

- Bash, GNU coreutils (`cp`, `realpath`, `mktemp`, `sha256sum`, etc.), `find`, `grep`, `sed`, `pgrep` (usually from `procps`), and `7z` or `7zz` (7-Zip).
- Enough temporary disk space to stage a copy of the files and to create the compressed archive.
- For automatic application stop/restart from root cron, run **as root** with `--user USER`, `--client CLIENT`, and `--package PACKAGE`. The program is stopped with SIGTERM and given up to 60 seconds to exit. It is restarted as the desktop user in the captured GUI environment. Requires `runuser`, `setsid`, `awk`, `getent`, `pgrep`, and access to `/proc`. A restore still requires applications to be closed manually.

Examples for installing 7-Zip:

```bash
# Arch / Manjaro
sudo pacman -S 7zip

# Debian / Ubuntu (package name may vary by release)
sudo apt install 7zip

# Fedora
sudo dnf install 7zip
```

## Unattended backups with root cron (no prompts)

The script is **non-interactive**: no confirmation questions and no ZIP password prompt. An encrypted backup **requires** `--password-file FILE`, and an ambiguous profile layout requires `--source DIR`. These conditions cause a nonzero exit instead of waiting for input. A restore into an existing matching profile container requires explicit `--merge`; a full restore refuses to replace an existing directory.

Root directly runs the backup with an explicit target user and installation variant. **Do not use `runuser` around the script** when automatic stop/restart is needed: root needs permission to inspect the application's process and session environment. The restart itself runs with the target user's UID.

Create a protected password file (prefer `/root/.config/betterbird-backup/password` with mode `600`) and do not store it in the backup source or publish it. Example for an installed native Betterbird:

```cron
# root crontab: sudo crontab -e
15 3 * * * /usr/bin/flock -n /run/lock/betterbird-backup.lock /usr/local/bin/betterbird-backup.sh backup --user roman --client betterbird --package native --mode full --source /home/roman/.thunderbird --output /mnt/backup/Betterbird --encrypt --password-file /root/.config/betterbird-backup/password >> /var/log/betterbird-backup.log 2>&1
```

Flatpak Thunderbird example:

```bash
sudo /usr/local/bin/betterbird-backup.sh backup \
  --user roman --client thunderbird --package flatpak \
  --mode full --source /home/roman/.var/app/org.mozilla.Thunderbird/.thunderbird \
  --output /mnt/backup/Thunderbird
```

Other values: `--client betterbird|thunderbird`, `--package native|flatpak|snap`. Snap launcher is supported for **Thunderbird only**. Native includes distribution packages and tarball installations when the executable is on PATH. There is no reliable universal indicator for which of multiple installations the user **prefers**. The script will not guess; explicitly select the desired client and package. If you run two different clients against the same profile, do not back up the shared profile while the other client remains open.

Behavior when the selected application is running:

1. Identify its main process belonging to the requested desktop account and packaging type.
2. Capture DISPLAY/WAYLAND_DISPLAY, XDG_RUNTIME_DIR, DBUS_SESSION_BUS_ADDRESS, and related session variables from its process environment.
3. Send SIGTERM and wait up to 60 seconds for closure. Never force-kill the application; refuse the backup if it remains running.
4. Create and test the ZIP archive. If the application had been running, attempt restart **even if the backup fails**.
5. If the application was not running, leave it stopped. If no usable GUI session is found, refuse to stop the process.

**Operational warning:** SIGTERM is not equivalent to requesting graceful shutdown through a desktop GUI. Test that unsent drafts, compose windows, and extension state survive this behavior on your version. A `runuser`/`setsid` restart is best effort, not proof that the GUI successfully launched. The process matcher assumes ordinary Betterbird/Thunderbird Linux main-process names and Flatpak/Snap environment markers; custom wrappers, unusual process naming, multiple identical running instances, or Flatpak access to the shared native profile may require manual handling. Protect backups from unintended access and verify the destination mount exists before starting cron.

Encryption caveat: 7-Zip AES-256 ZIP leaves filenames exposed and the script sends its password to 7-Zip as a process argument. Backup archives include sensitive profile and authentication data even in `settings-no-passwords` mode. Restore full archives only into an empty/nonexistent target; `--merge` is for matching settings snapshots only.

A non-interactive restore of encrypted settings into an *existing and matching* container would look like:

```bash
./betterbird-backup.sh restore /path/to/archive.zip \
  --destination /home/roman/.thunderbird \
  --merge --password-file /home/roman/.config/betterbird-backup/zip-password
```

A full restore never overwrites an existing destination; remove/rename it separately after verifying it is safe to do so.

## Backup

```bash
# Full backup (including mail and saved passwords)
./betterbird-backup.sh backup --mode full

# Selected configuration and saved passwords, but no message bodies
./betterbird-backup.sh backup --mode settings --encrypt --password-file "$HOME/.config/betterbird-backup/zip-password"

# Selected configuration excluding the central saved-login database
./betterbird-backup.sh backup --mode settings-no-passwords

# Explicit Thunderbird Flatpak profile
./betterbird-backup.sh backup --mode full --source "$HOME/.var/app/org.mozilla.Thunderbird/.thunderbird"

# Explicit Betterbird Flatpak profile
./betterbird-backup.sh backup --mode full --source "$HOME/.var/app/eu.betterbird.Betterbird/.thunderbird"

# Override output directory
./betterbird-backup.sh backup --mode full --output /mnt/backups
```

| Mode | Content |
| --- | --- |
| `full` | Complete profile **container**: mail, account configuration, add-ons, local calendar data, and saved logins |
| `settings` | Selected preferences, extensions, address books, calendars, mail filter rules and saved logins, **not** mail content |
| `settings-no-passwords` | Same selected configuration but excludes `logins.json` and `key4.db`; **NOT secret-free** |

### Passwords and sensitive data

Even the `settings-no-passwords` mode can contain OAuth tokens, account identifiers, custom extension credentials, calendar secrets, authentication state or other private information. Do not publish backup files to GitHub or share them without independent review. The `full` and `settings` modes can contain saved passwords. A Thunderbird primary password, if set, may still be required after restore.

## Restore

```bash
# Default restore destination: ~/.thunderbird
./betterbird-backup.sh restore /path/to/backup.zip

# Restore to Betterbird Flatpak container
./betterbird-backup.sh restore /path/to/backup.zip \
  --destination "$HOME/.var/app/eu.betterbird.Betterbird/.thunderbird"

# Restore to Thunderbird Flatpak container
./betterbird-backup.sh restore /path/to/backup.zip \
  --destination "$HOME/.var/app/org.mozilla.Thunderbird/.thunderbird"

# Merge settings into an existing matching profile container
./betterbird-backup.sh restore /path/to/settings-backup.zip --merge
```

- **A full backup does not overwrite an existing destination.** Rename or move the old profile container before restoring.
- Settings-only restore with `--merge` requires `profiles.ini` to match **exactly**; no interactive confirmation is requested. Matching files are overwritten, while existing mail content remains untouched. Always make a backup first.
- The script does **not** automatically rewrite profile paths, fix access permissions of custom external folders, migrate accounts across incompatible versions, or include files stored **outside** the profile container (e.g., external profile locations or external signature files).
- For Betterbird ↔ Thunderbird migrations, check *application/profile version compatibility*. Both generally share the same file layout, but using a profile with an older program version may break it. Prefer a compatible ESR version.

## Encryption and archive integrity

`--encrypt` uses 7-Zip's **ZIP AES-256** encryption and reads a password file (no prompt). Internally 7-Zip receives that password on its command line; this is a process-visibility caveat. ZIP **file names remain visible**. Use 7-Zip to restore, because not every ZIP utility understands ZIP AES-256. Without the password the files cannot be recovered.

The script writes a sidecar `.sha256` checksum and checks it during restore if present. This detects accidental changes, but is **not** a signature or proof of authenticity.

## Known limitations

- Linux/Bash only; no Windows/macOS support.
- Detection covers common profile containers, **not** externally referenced absolute paths in `profiles.ini`.
- Settings-only mode includes selected files; changes to Thunderbird or Betterbird may introduce new settings not covered by the selection.
- ZIP temporary staging can consume significant disk space for large mail stores.
- Backups attempt to close/restart the explicitly selected application; snapshots require the profile to be quiescent. Running applications that share profiles or nonstandard launchers remain a risk.
- Automatic GUI restart under cron is best effort; it should be validated in the actual desktop environment.
- Validated with `bash -n` syntax checking only; independent functional tests are still required, including stop/restart in KDE/GNOME, encrypted restore and Flatpak/Snap migrations.

## Upstream references

- [Betterbird: profile compatibility and paths](https://betterbird.eu/support/)
- [Betterbird Flatpak: profile location and migration](https://github.com/flathub/eu.betterbird.Betterbird)
- [Thunderbird Flatpak: profile location and migration](https://github.com/flathub/org.mozilla.Thunderbird)
- [Thunderbird Snap: profile notes](https://support.mozilla.org/en-US/kb/installing-thunderbird-linux)

## License

MIT License; see `LICENSE`.
