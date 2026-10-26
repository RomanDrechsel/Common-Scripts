#!/usr/bin/env bash
# Betterbird profile backup and restore for Linux.
# Requires 7z or 7zz for ZIP archives with optional AES-256 encryption.
set -Eeuo pipefail
umask 077

PROGRAM=${0##*/}
BACKUP_DIR="${HOME}/Backups/Betterbird"
BACKUP_DIR_SET=0
CLIENT="auto"
PACKAGE="auto"
TARGET_USER=""
TARGET_HOME=""
TARGET_UID=""
RESTART_NEEDED=0
RESTART_DONE=0
RESTART_CLIENT=""
RESTART_PACKAGE=""
declare -a RESTART_ENV=()
declare -a MATCHING_PIDS=()
SOURCE_DIR=""
RESTORE_DIR=""
MODE=""
ENCRYPT=0
PASSWORD_FILE=""
PASSWORD=""
ACTION=""
ARCHIVE=""
SEVENZIP=""
WORKDIR=""

usage() {
    cat <<USAGE
Usage:
  $PROGRAM backup --user USER --client betterbird|thunderbird --package native|flatpak|snap --mode full|settings|settings-no-passwords [--source DIR] [--output DIR] [--encrypt --password-file FILE]
  $PROGRAM restore ARCHIVE [--client auto|betterbird|thunderbird] [--destination DIR] [--merge] [--password-file FILE]

Options:
  --mode          full: all profile data (including passwords and mail)
                  settings: settings and saved passwords, no mail
                  settings-no-passwords: settings without Betterbird's login/key database
  --encrypt       protect ZIP contents with AES-256 (requires --password-file)
  --password-file path to a file containing the ZIP password, usable without terminal input
  --client        Which application: betterbird or thunderbird (auto is allowed for closed profiles)
  --package       Which installation: native, flatpak, snap, or auto
  --user          Desktop account (required when run as root)
  --source        Profile container (directory with profiles.ini)
  --output        backup directory (default: $BACKUP_DIR)
  --destination   directory to restore the profile container into
  --merge         permit noninteractive settings restore into existing matching profiles

Examples:
  $PROGRAM backup --user alice --client betterbird --package native --mode full --encrypt --password-file /root/.config/bb-password
  $PROGRAM backup --mode settings-no-passwords --output /mnt/backups
  $PROGRAM restore ~/Backups/Betterbird/betterbird-full-2026-10-26_140000.zip
  $PROGRAM restore ~/Backups/Betterbird/betterbird-settings-2026-10-26_140000.zip --merge
USAGE
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
log() { printf '%s\n' "$*"; }
cleanup() { [[ -z "$WORKDIR" ]] || rm -rf -- "$WORKDIR"; }

# Restart on successful backup AND on failed backup, but never while the process is still alive.
finish() {
    local status=$?
    trap - EXIT
    cleanup
    if (( RESTART_NEEDED && ! RESTART_DONE )); then
        if ! restart_client; then
            printf 'ERROR: Automatic restart failed. Start %s manually.\n' "$RESTART_CLIENT" >&2
            (( status != 0 )) || status=1
        fi
    fi
    exit "$status"
}

resolve_user() {
    local entry
    if (( EUID == 0 )); then
        [[ -n "$TARGET_USER" ]] || die 'Root must specify --user USER (never use root HOME implicitly).'
    else
        [[ -z "$TARGET_USER" ]] && TARGET_USER=$(id -un)
        [[ "$TARGET_USER" == "$(id -un)" ]] || die 'Only root can select another --user.'
    fi
    entry=$(getent passwd "$TARGET_USER") || die "Unknown account: $TARGET_USER"
    IFS=: read -r _ _ TARGET_UID _ _ TARGET_HOME _ <<< "$entry"
    [[ "$TARGET_UID" =~ ^[0-9]+$ && -d "$TARGET_HOME" ]] || die 'Invalid user/home directory.'
    [[ "$TARGET_UID" != 0 ]] || die 'Do not back up a root desktop session.'
    if [[ -z "$SOURCE_DIR" ]]; then HOME=$TARGET_HOME; fi
    (( BACKUP_DIR_SET )) || BACKUP_DIR="$TARGET_HOME/Backups/Betterbird"
}

# Matches only the requested application AND package, under the requested account.
# /proc/*/environ is read as root; process discovery intentionally never guesses a preferred app.
process_package() {
    local pid=$1 variable value
    local pkg=native
    [[ -r "/proc/$pid/environ" ]] || { printf 'unknown'; return; }
    while IFS= read -r -d '' variable; do
        case "$variable" in
            FLATPAK_ID=eu.betterbird.Betterbird|FLATPAK_ID=org.mozilla.Thunderbird) pkg=flatpak ;;
            SNAP_NAME=thunderbird|SNAP_INSTANCE_NAME=thunderbird) pkg=snap ;;
        esac
    done < "/proc/$pid/environ"
    # Some Flatpak versions do not expose FLATPAK_ID inside the process environ.
    if [[ "$pkg" == native && -f "/proc/$pid/root/.flatpak-info" ]]; then pkg=flatpak; fi
    printf '%s' "$pkg"
}

collect_client_pids() {
    MATCHING_PIDS=()
    local pid comm uid pkg
    for proc in /proc/[0-9]*; do
        pid=${proc##*/}
        [[ -r "$proc/comm" && -r "$proc/status" ]] || continue
        IFS= read -r comm < "$proc/comm" || continue
        [[ "$comm" == "$CLIENT" ]] || continue
        uid=$(awk '/^Uid:/ {print $2; exit}' "$proc/status")
        [[ "$uid" == "$TARGET_UID" ]] || continue
        pkg=$(process_package "$pid")
        [[ "$pkg" == "$PACKAGE" ]] && MATCHING_PIDS+=("$pid")
    done
}

capture_session() {
    local pid=$1 entry key value
    local -a env_names=(DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP)
    RESTART_ENV=()
    while IFS= read -r -d '' entry; do
        key=${entry%%=*}; value=${entry#*=}
        case " ${env_names[*]} " in *" $key "*) RESTART_ENV+=("$entry") ;; esac
    done < "/proc/$pid/environ"
    local has_display=0
    for entry in "${RESTART_ENV[@]}"; do
        case "$entry" in DISPLAY=*|WAYLAND_DISPLAY=*) has_display=1 ;; esac
    done
    (( has_display )) || die 'No GUI session (DISPLAY/WAYLAND_DISPLAY) for running client; refusing to stop it.'
}

restart_client() {
    (( RESTART_NEEDED )) || return 0
    # Never create duplicate windows if something restarted the application meanwhile.
    collect_client_pids
    if ((${#MATCHING_PIDS[@]})); then
        log 'Application is already running again; skipping restart.'
        RESTART_DONE=1
        return 0
    fi
    local -a command=()
    case "$RESTART_PACKAGE:$RESTART_CLIENT" in
        native:betterbird|native:thunderbird) command=("$RESTART_CLIENT") ;;
        flatpak:betterbird) command=(flatpak run eu.betterbird.Betterbird) ;;
        flatpak:thunderbird) command=(flatpak run org.mozilla.Thunderbird) ;;
        snap:thunderbird) command=(snap run thunderbird) ;;
        *) return 1 ;;
    esac
    log "Restarting $RESTART_CLIENT ($RESTART_PACKAGE) for $TARGET_USER..."
    if (( EUID == 0 )); then
        runuser -u "$TARGET_USER" -- env "HOME=$TARGET_HOME" "${RESTART_ENV[@]}" setsid "${command[@]}" </dev/null >/dev/null 2>&1 &
    else
        env "HOME=$TARGET_HOME" "${RESTART_ENV[@]}" setsid "${command[@]}" </dev/null >/dev/null 2>&1 &
    fi
    RESTART_DONE=1
    return 0
}

stop_for_backup() {
    [[ "$CLIENT" != auto && "$PACKAGE" != auto ]] || {
        # If the chosen container exists but client/package is ambiguous, abort rather than kill something else.
        die 'To safely stop/restart an application, specify both --client and --package.'
    }
    collect_client_pids
    if ((${#MATCHING_PIDS[@]} == 0)); then
        if [[ "$PACKAGE" == native ]]; then
            local other=betterbird
            [[ "$CLIENT" == betterbird ]] && other=thunderbird
            pgrep -u "$TARGET_USER" -x "$other" >/dev/null 2>&1 && die "Other client ($other) is running and may share the selected profile."
        fi
        log 'Selected application is not running.'
        return 0
    fi
    ((${#MATCHING_PIDS[@]} == 1)) || die 'Multiple matching application processes; refusing to guess which instance to restart.'
    local pid=${MATCHING_PIDS[0]} attempt
    # Native clients share ~/.thunderbird: never back it up while the other client is running.
    if [[ "$PACKAGE" == native ]]; then
        if [[ "$CLIENT" == betterbird ]]; then
            pgrep -u "$TARGET_USER" -x thunderbird >/dev/null 2>&1 && die 'Thunderbird also runs and may share ~/.thunderbird; close it first.'
        else
            pgrep -u "$TARGET_USER" -x betterbird >/dev/null 2>&1 && die 'Betterbird also runs and may share ~/.thunderbird; close it first.'
        fi
    fi
    capture_session "$pid"
    RESTART_CLIENT=$CLIENT
    RESTART_PACKAGE=$PACKAGE
    RESTART_NEEDED=1
    log "Gracefully stopping $CLIENT ($PACKAGE), PID $pid..."
    kill -TERM "$pid" || die 'Could not signal application.'
    for (( attempt=0; attempt<60; attempt++ )); do
        collect_client_pids
        ((${#MATCHING_PIDS[@]} == 0)) && { log 'Application closed.'; return 0; }
        sleep 1
    done
    die 'Application did not close within 60 seconds; backup aborted (no SIGKILL).'
}

read_password() {
    [[ -n "$PASSWORD_FILE" ]] || die "Encrypted archives require --password-file; interactive prompts are disabled."
    [[ -f "$PASSWORD_FILE" && -r "$PASSWORD_FILE" ]] || die "Password file is not readable: $PASSWORD_FILE"
    local permissions
    permissions=$(stat -c %a -- "$PASSWORD_FILE")
    if (( (8#$permissions & 077) != 0 )); then
        die "Password file must not grant group/other permissions: $PASSWORD_FILE (chmod 600)."
    fi
    IFS= read -r PASSWORD < "$PASSWORD_FILE" || [[ -n "$PASSWORD" ]]
    [[ -n "$PASSWORD" ]] || die "Password file is empty: $PASSWORD_FILE"
    [[ "$PASSWORD" != *$'\r'* ]] || die "Password must not contain carriage returns."
    log "WARNING: 7-Zip receives the password as a command-line argument (potentially visible in process listings)."
}

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

find_7zip() {
    if command -v 7zz >/dev/null 2>&1; then SEVENZIP=$(command -v 7zz)
    elif command -v 7z >/dev/null 2>&1; then SEVENZIP=$(command -v 7z)
    else die 'Please install 7zip (7z or 7zz). On Manjaro: sudo pacman -S 7zip'; fi
}

check_closed() {
    if command -v pgrep >/dev/null 2>&1 && pgrep -u "$TARGET_USER" -x 'betterbird|thunderbird' >/dev/null 2>&1; then
        die 'Close Betterbird/Thunderbird before restore.'
    fi
}

find_source() {
    if [[ -n "$SOURCE_DIR" ]]; then return; fi
    local candidate
    local -a candidates=()
    case "$CLIENT:$PACKAGE" in
        betterbird:native|thunderbird:native) candidates=("$TARGET_HOME/.thunderbird") ;;
        betterbird:flatpak) candidates=("$TARGET_HOME/.var/app/eu.betterbird.Betterbird/.thunderbird") ;;
        thunderbird:flatpak) candidates=("$TARGET_HOME/.var/app/org.mozilla.Thunderbird/.thunderbird") ;;
        thunderbird:snap) candidates=("$TARGET_HOME/snap/thunderbird/common/.thunderbird" "$TARGET_HOME/snap/thunderbird/current/.thunderbird") ;;
        betterbird:snap) die 'Betterbird Snap is not supported.' ;;
        *) candidates=("$TARGET_HOME/.thunderbird" "$TARGET_HOME/.var/app/eu.betterbird.Betterbird/.thunderbird" "$TARGET_HOME/.var/app/org.mozilla.Thunderbird/.thunderbird" "$TARGET_HOME/snap/thunderbird/common/.thunderbird") ;;
    esac
    local -a found=( )
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate/profiles.ini" ]]; then
            local already=0 existing
            for existing in "${found[@]}"; do
                [[ "$(realpath -e "$existing")" == "$(realpath -e "$candidate")" ]] && already=1
            done
            (( already )) || found+=("$candidate")
        fi
    done
    if ((${#found[@]} == 1)); then SOURCE_DIR="${found[0]}"; return; fi
    if ((${#found[@]} > 1)); then
        printf 'Multiple profile containers found; select one using --source DIR:\n' >&2
        printf '  %s\n' "${found[@]}" >&2
        exit 1
    fi
    die 'No profiles.ini found; use --source DIR.' 
}

# Select portable configuration files without copying mail folders or caches.
copy_settings() {
    local source="$1" dest="$2" root profile name file
    mkdir -p "$dest"
    for name in profiles.ini installs.ini; do
        [[ ! -f "$source/$name" ]] || cp -a -- "$source/$name" "$dest/"
    done
    while IFS= read -r -d '' profile; do
        root="${profile#"$source"/}"
        mkdir -p "$dest/$root"
        for name in prefs.js user.js xulstore.json folderTree.json session.json \
            search.json.mozlz4 logins.json key4.db cert9.db pkcs11.txt \
            permissions.sqlite content-prefs.sqlite handlers.json mimeTypes.rdf \
            times.json extensions.json extension-preferences.json addonStartup.json.lz4 \
            addons.json containers.json virtualFolders.dat abook.mab history.mab \
            permissions.sqlite-wal permissions.sqlite-shm; do
            if [[ "$MODE" == settings-no-passwords ]]; then
                case "$name" in logins.json|key4.db) continue ;; esac
            fi
            [[ ! -f "$profile/$name" ]] || cp -a -- "$profile/$name" "$dest/$root/"
        done
        for name in extensions chrome calendar-data; do
            [[ ! -e "$profile/$name" ]] || cp -a -- "$profile/$name" "$dest/$root/"
        done
        while IFS= read -r -d '' file; do
            name=${file##*/}
            case "$name" in
                global-messages-db.sqlite*|cache2.sqlite*|startupCache*) continue ;;
            esac
            cp -a -- "$file" "$dest/$root/$name"
        done < <(find "$profile" -maxdepth 1 -type f \( -name '*.sqlite' -o -name '*.sqlite-wal' -o -name '*.sqlite-shm' \) -print0)
        # Preserve mail filters but exclude actual message files.
        local folder relative
        for folder in ImapMail Mail; do
            if [[ -d "$profile/$folder" ]]; then
                while IFS= read -r -d '' file; do
                    relative=${file#"$profile"/}
                    mkdir -p -- "$dest/$root/${relative%/*}"
                    cp -a -- "$file" "$dest/$root/$relative"
                done < <(find "$profile/$folder" -type f -name msgFilterRules.dat -print0)
            fi
        done
    done < <(find "$source" -mindepth 1 -maxdepth 1 -type d -print0)
}

prepare_payload() {
    mkdir -p "$WORKDIR/payload"
    if [[ "$MODE" == full ]]; then
        cp -a -- "$SOURCE_DIR/." "$WORKDIR/payload/"
    else
        copy_settings "$SOURCE_DIR" "$WORKDIR/payload"
    fi
    printf 'betterbird-backup-v1\nmode=%s\n' "$MODE" > "$WORKDIR/payload/.betterbird-backup-manifest"
}

backup() {
    [[ "$MODE" == full || "$MODE" == settings || "$MODE" == settings-no-passwords ]] || die 'Please select a valid --mode.'
    find_source
    [[ -f "$SOURCE_DIR/profiles.ini" ]] || die "No profiles.ini in source directory: $SOURCE_DIR"
    [[ "$CLIENT" =~ ^(betterbird|thunderbird)$ && "$PACKAGE" =~ ^(native|flatpak|snap)$ ]] || die 'Use explicit --client and --package for safe automated backup.'
    stop_for_backup
    mkdir -p -- "$BACKUP_DIR"
    BACKUP_DIR=$(realpath -- "$BACKUP_DIR")
    SOURCE_DIR=$(realpath -- "$SOURCE_DIR")
    case "$BACKUP_DIR/" in "$SOURCE_DIR/"*) die 'Backup destination must not be inside the source directory.' ;; esac
    WORKDIR=$(mktemp -d)
    prepare_payload
    local stamp base tmpfile result
    stamp=$(date '+%Y-%m-%d_%H%M%S')
    base="$BACKUP_DIR/betterbird-$MODE-$stamp.zip"
    [[ ! -e "$base" ]] || die "Backup already exists: $base"
    tmpfile="$WORKDIR/archive.zip"
    log "Backing up '$MODE' from $SOURCE_DIR"
    if (( ENCRYPT )); then
        log 'Encrypting ZIP contents with AES-256; file names remain visible.'
        (cd "$WORKDIR/payload" && "$SEVENZIP" a -tzip -mx=5 -mem=AES256 "-p$PASSWORD" "$tmpfile" . >/dev/null)
    else
        (cd "$WORKDIR/payload" && "$SEVENZIP" a -tzip -mx=5 "$tmpfile" .)
    fi
    [[ -s "$tmpfile" ]] || die 'Archive was not created.'
    if (( ENCRYPT )); then "$SEVENZIP" t "-p$PASSWORD" "$tmpfile" >/dev/null; else "$SEVENZIP" t "$tmpfile" >/dev/null; fi
    mv -- "$tmpfile" "$base"
    (cd "$BACKUP_DIR" && sha256sum -- "${base##*/}" > "${base##*/}.sha256")
    log "Created: $base"
    log "Checksum: $base.sha256"
}

restore() {
    [[ -f "$ARCHIVE" ]] || die "Archive not found: $ARCHIVE"
    check_closed
    local origin manifest archive_dir basename_archive saved_mode
    ARCHIVE=$(realpath -- "$ARCHIVE")
    archive_dir=${ARCHIVE%/*}
    basename_archive=${ARCHIVE##*/}
    if [[ -f "$ARCHIVE.sha256" ]]; then
        (cd "$archive_dir" && sha256sum -c -- "$basename_archive.sha256") || die 'Checksum mismatch.'
    fi
    WORKDIR=$(mktemp -d)
    log 'Testing and extracting archive without interactive prompts...'
    local -a password_args=( -p- )
    if [[ -n "$PASSWORD_FILE" ]]; then
        read_password
        password_args=( "-p$PASSWORD" )
    fi
    "$SEVENZIP" t "${password_args[@]}" "$ARCHIVE" </dev/null >/dev/null || die 'Archive integrity check failed or archive password missing/incorrect.'
    "$SEVENZIP" x "${password_args[@]}" -y "-o$WORKDIR/extracted" "$ARCHIVE" </dev/null >/dev/null || die 'Extraction failed.'
    manifest="$WORKDIR/extracted/.betterbird-backup-manifest"
    [[ -f "$manifest" ]] || die 'Not a supported Betterbird backup (manifest missing).'
    grep -qx 'betterbird-backup-v1' "$manifest" || die 'Unsupported backup format.'
    saved_mode=$(sed -n 's/^mode=//p' "$manifest" | head -n 1)
    case "$saved_mode" in full|settings|settings-no-passwords) ;; *) die 'Invalid backup mode.' ;; esac
    [[ -f "$WORKDIR/extracted/profiles.ini" ]] || die 'profiles.ini missing.'
    if [[ -z "$RESTORE_DIR" ]]; then
        case "$CLIENT" in
            betterbird) RESTORE_DIR="$HOME/.var/app/eu.betterbird.Betterbird/.thunderbird" ;;
            thunderbird) RESTORE_DIR="$HOME/.var/app/org.mozilla.Thunderbird/.thunderbird" ;;
            auto) RESTORE_DIR="$HOME/.thunderbird" ;;
            *) die "Unknown client: $CLIENT" ;;
        esac
    fi
    RESTORE_DIR=$(realpath -m -- "$RESTORE_DIR")
    [[ "$RESTORE_DIR" != / && "$RESTORE_DIR" != "$HOME" ]] || die 'Unsafe restore destination.'
    if [[ -e "$RESTORE_DIR" ]]; then
        if [[ "$saved_mode" == full ]]; then
            die "Destination exists: $RESTORE_DIR. Rename it before restoring a full backup."
        fi
        (( MERGE )) || die "Destination exists: $RESTORE_DIR. Use --merge to explicitly allow settings import."
        [[ -f "$RESTORE_DIR/profiles.ini" ]] || die '--merge requires an existing Betterbird profile container.'
        cmp -s -- "$WORKDIR/extracted/profiles.ini" "$RESTORE_DIR/profiles.ini" || die 'Profile definitions differ. Refusing unsafe merge. Restore into a new directory or align profiles manually.'
        log 'WARNING: --merge explicitly authorizes overwriting matching settings files.'
        # Restore settings over existing profiles, preserving mail content.
        cp -a -- "$WORKDIR/extracted/." "$RESTORE_DIR/"
    else
        mkdir -p -- "$RESTORE_DIR"
        cp -a -- "$WORKDIR/extracted/." "$RESTORE_DIR/"
    fi
    rm -f -- "$RESTORE_DIR/.betterbird-backup-manifest"
    log "Restored $saved_mode backup to: $RESTORE_DIR"
    log 'If original profiles lived outside this directory, adjust profiles.ini and copy external data separately.'
}

MERGE=0
[[ $# -gt 0 ]] || { usage; exit 1; }
ACTION=$1; shift
case "$ACTION" in
    backup)
        while (($#)); do
            case "$1" in
                --mode) [[ $# -ge 2 ]] || die '--mode needs a value'; MODE=$2; shift 2 ;;
                --client) [[ $# -ge 2 ]] || die '--client needs a value'; CLIENT=$2; shift 2 ;;
                --package) [[ $# -ge 2 ]] || die '--package needs a value'; PACKAGE=$2; shift 2 ;;
                --user) [[ $# -ge 2 ]] || die '--user needs a value'; TARGET_USER=$2; shift 2 ;;
                --encrypt) ENCRYPT=1; shift ;;
                --password-file) [[ $# -ge 2 ]] || die '--password-file needs a path'; PASSWORD_FILE=$2; shift 2 ;;
                --source) [[ $# -ge 2 ]] || die '--source needs a path'; SOURCE_DIR=$2; shift 2 ;;
                --output) [[ $# -ge 2 ]] || die '--output needs a path'; BACKUP_DIR=$2; BACKUP_DIR_SET=1; shift 2 ;;
                -h|--help) usage; exit 0 ;;
                *) die "Unknown option: $1" ;;
            esac
        done
        resolve_user
        find_7zip
        if (( ENCRYPT )); then read_password; elif [[ -n "$PASSWORD_FILE" ]]; then die "--password-file requires --encrypt for backup."; fi
        backup
        ;;
    restore)
        [[ $# -gt 0 ]] || die 'Missing archive argument.'
        ARCHIVE=$1; shift
        while (($#)); do
            case "$1" in
                --destination) [[ $# -ge 2 ]] || die '--destination needs a path'; RESTORE_DIR=$2; shift 2 ;;
                --client) [[ $# -ge 2 ]] || die '--client needs a value'; CLIENT=$2; shift 2 ;;
                --package) [[ $# -ge 2 ]] || die '--package needs a value'; PACKAGE=$2; shift 2 ;;
                --user) [[ $# -ge 2 ]] || die '--user needs a value'; TARGET_USER=$2; shift 2 ;;
                --merge) MERGE=1; shift ;;
                --password-file) [[ $# -ge 2 ]] || die '--password-file needs a path'; PASSWORD_FILE=$2; shift 2 ;;
                -h|--help) usage; exit 0 ;;
                *) die "Unknown option: $1" ;;
            esac
        done
        resolve_user
        find_7zip
        restore
        ;;
    -h|--help) usage ;;
    *) die "Unknown action: $ACTION" ;;
esac
