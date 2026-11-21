#!/usr/bin/env bash
# Back up and restore Betterbird settings without mail messages.
# Requires: bash, zip, unzip, realpath, find, mktemp, cp, mv.

_betterbird_error() {
    printf 'Error: %s\n' "$*" >&2
}

_betterbird_check_tools() {
    local tool
    for tool in realpath find mktemp zip unzip; do
        command -v "$tool" >/dev/null 2>&1 || {
            _betterbird_error "Required command not found: $tool"
            return 1
        }
    done
}

_betterbird_check_closed() {
    local profile="$1" status

    # When sourced together with the session manager, use its exact same
    # process detection instead of a separate pgrep -x heuristic.
    if declare -F _mailclient_profile_running >/dev/null 2>&1; then
        _mailclient_profile_running "$profile"
        status=$?
        if (( status == 0 )); then
            _betterbird_error "Mail client is still running. Close it before exporting: $profile"
            return 1
        elif (( status != 1 )); then
            _betterbird_error "Unable to verify mail-client status."
            return 1
        fi
    else
        # Standalone exports must be conservative as well. Match full command
        # lines, since Flatpak applications may rename their process comm.
        if pgrep -f '(^|/)(betterbird|betterbird-bin|thunderbird|thunderbird-bin)([[:space:]]|$)' >/dev/null 2>&1; then
            _betterbird_error 'Betterbird/Thunderbird may still be running. Close it before exporting.'
            return 1
        fi
    fi

    # Leftover lock files alone are not proof of a live process.
    if [[ -e "$profile/.parentlock" || -L "$profile/.parentlock" ||
          -e "$profile/lock" || -L "$profile/lock" ]]; then
        printf 'Note: Profile has a lock file, but no matching running mail client was found.\n' >&2
    fi
}

betterbird_export_settings() {
    if (( $# != 2 )); then
        _betterbird_error 'Usage: betterbird_export_settings <archive.zip> <betterbird-profile>'
        return 2
    fi

    local archive="$1" profile="$2"
    local archive_dir temp_archive entry file dir
    local -a entries=()

    _betterbird_check_tools || return 1
    [[ -d "$profile" ]] || { _betterbird_error "Profile directory not found: $profile"; return 1; }
    profile="$(realpath -e -- "$profile")" || return 1
    archive="$(realpath -m -- "$archive")" || return 1
    archive_dir="$(dirname -- "$archive")"

    case "$archive" in
        "$profile"/*) _betterbird_error 'Archive must be outside the profile directory.'; return 1 ;;
    esac

    _betterbird_check_closed "$profile" || return 1
    [[ -f "$profile/prefs.js" ]] || {
        _betterbird_error 'This does not appear to be a Betterbird profile (prefs.js is missing).'
        return 1
    }
    mkdir -p -- "$archive_dir" || return 1

    # Restrict the permissions of backups containing stored credentials.
    local old_umask
    old_umask="$(umask)"
    umask 077
    temp_archive="$(mktemp -- "$archive_dir/.betterbird-backup.XXXXXXXX.zip")" || {
        umask "$old_umask"
        return 1
    }
    umask "$old_umask"
    rm -f -- "$temp_archive" || return 1

    # Run file discovery and zip from inside the profile, preserving relative paths.
    (
        umask 077
        cd -- "$profile" || exit 1

        for entry in \
            prefs.js user.js session.json xulstore.json folderTree.json \
            panacea.dat virtualFolders.dat folderCache.json \
            search.json.mozlz4 handlers.json mimeTypes.rdf times.json \
            logins.json logins.db logins-backup.json key4.db cert9.db pkcs11.txt \
            encrypted-openpgp-passphrase.txt secring.gpg pubring.gpg \
            openpgp.sqlite permissions.sqlite content-prefs.sqlite \
            compatibility.ini extensions.json extension-preferences.json \
            addonStartup.json.lz4 addons.json containers.json \
            calendar-data extensions chrome storage \
            abook.mab history.mab; do
            [[ -e "$entry" ]] && entries+=("$entry")
        done

        # Include top-level SQLite databases (address books, calendars, add-ons),
        # including WAL files, but not the rebuildable global search index.
        while IFS= read -r -d '' file; do
            file="${file#./}"
            case "$file" in
                global-messages-db.sqlite|global-messages-db.sqlite-wal|global-messages-db.sqlite-shm|cache2.sqlite*) continue ;;
            esac
            entries+=("$file")
        done < <(find . -maxdepth 1 -type f \( \
            -name '*.sqlite' -o -name '*.sqlite-wal' -o -name '*.sqlite-shm' -o \
            -name '*.db-wal' -o -name '*.db-shm' \
        \) -print0)

        # Include message filter rules and POP3 download state, not messages.
        for dir in ImapMail Mail News; do
            [[ -d "$dir" ]] || continue
            while IFS= read -r -d '' file; do
                entries+=("${file#./}")
            done < <(find "$dir" -type f \( \
                -name 'msgFilterRules.dat' -o -name 'popstate.dat' \
            \) -print0)
        done

        ((${#entries[@]} > 0)) || { _betterbird_error 'No settings files found.'; exit 1; }

        # Avoid cache/mail files even if they appear inside a selected directory.
        zip -q -r "$temp_archive" "${entries[@]}" \
            -x '*/cache2/*' '*/startupCache/*' '*.msf' \
               '*/cur/*' '*/new/*' '*/tmp/*'
    ) || { rm -f -- "$temp_archive"; _betterbird_error 'ZIP creation failed.'; return 1; }

    # A marker distinguishes these archives from arbitrary ZIP files.
    local marker_dir
    marker_dir="$(mktemp -d)" || { rm -f -- "$temp_archive"; return 1; }
    printf 'betterbird-settings-backup-v1\n' > "$marker_dir/.betterbird-settings-backup"
    (cd "$marker_dir" && zip -q "$temp_archive" .betterbird-settings-backup)
    local marker_status=$?
    rm -rf -- "$marker_dir"
    if ((marker_status != 0)) || ! unzip -tqq "$temp_archive"; then
        rm -f -- "$temp_archive"
        _betterbird_error 'Archive verification failed; previous backup remains unchanged.'
        return 1
    fi

    # Replace the old archive only after the new one has been verified.
    if ! mv -f -- "$temp_archive" "$archive"; then
        rm -f -- "$temp_archive"
        _betterbird_error 'Could not replace the archive.'
        return 1
    fi
    chmod 600 -- "$archive" || return 1
    printf 'Backup created: %s\n' "$archive"
}

betterbird_import_settings() {
    if (( $# != 2 )); then
        _betterbird_error 'Usage: betterbird_import_settings <archive.zip> <new-empty-profile>'
        return 2
    fi

    local archive="$1" profile="$2" parent staging entry
    _betterbird_check_tools || return 1
    [[ -f "$archive" ]] || { _betterbird_error "Archive not found: $archive"; return 1; }
    archive="$(realpath -e -- "$archive")" || return 1
    profile="$(realpath -m -- "$profile")" || return 1
    parent="$(dirname -- "$profile")"
    [[ -d "$parent" ]] || { _betterbird_error "Parent directory does not exist: $parent"; return 1; }

    _betterbird_check_closed "$profile" || return 1
    if [[ -L "$profile" ]]; then
        _betterbird_error 'Destination cannot be a symbolic link.'
        return 1
    fi
    if [[ -e "$profile" ]]; then
        [[ -d "$profile" ]] || { _betterbird_error 'Destination is not a directory.'; return 1; }
        if [[ -n "$(find "$profile" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
            _betterbird_error 'Destination profile must be empty. Existing profiles are never overwritten.'
            return 1
        fi
    fi

    if ! unzip -tqq "$archive" ||
       [[ "$(unzip -p "$archive" .betterbird-settings-backup 2>/dev/null)" != 'betterbird-settings-backup-v1' ]]; then
        _betterbird_error 'Archive is invalid or was not created by this script.'
        return 1
    fi

    # Reject unsafe paths in a ZIP before extracting anything.
    while IFS= read -r entry; do
        case "$entry" in
            /*|../*|*/../*|*/..|./*|*\\*|*'//'*)
                _betterbird_error "Unsafe path in archive: $entry"
                return 1 ;;
        esac
    done < <(unzip -Z -1 "$archive")

    staging="$(mktemp -d -- "$parent/.betterbird-restore.XXXXXXXX")" || return 1
    if ! unzip -qq "$archive" -d "$staging"; then
        rm -rf -- "$staging"
        _betterbird_error 'Could not extract the archive.'
        return 1
    fi
    rm -f -- "$staging/.betterbird-settings-backup"
    if [[ ! -f "$staging/prefs.js" ]]; then
        rm -rf -- "$staging"
        _betterbird_error 'The restored settings do not contain prefs.js.'
        return 1
    fi

    # Move the prepared directory into place; do not merge with any old profile.
    if [[ -d "$profile" ]] && ! rmdir -- "$profile"; then
        rm -rf -- "$staging"
        _betterbird_error 'Destination is no longer empty.'
        return 1
    fi
    if ! mv -- "$staging" "$profile"; then
        rm -rf -- "$staging"
        _betterbird_error 'Restore failed.'
        return 1
    fi
    chmod 700 -- "$profile" || return 1
    printf 'Settings restored to: %s\n' "$profile"
    printf 'Note: Mail messages are not included in this backup.\n'
}

# Allow both sourcing this file and executing it directly.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        export) shift; betterbird_export_settings "$@" ;;
        import) shift; betterbird_import_settings "$@" ;;
        *)
            printf 'Usage:\n  %s export <archive.zip> <profile>\n  %s import <archive.zip> <new-empty-profile>\n' "$0" "$0" >&2
            exit 2 ;;
    esac
fi
