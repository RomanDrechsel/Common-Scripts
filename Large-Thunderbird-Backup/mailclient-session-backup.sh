#!/usr/bin/env bash
# Stop a running Betterbird/Thunderbird (Flatpak or native), back up its settings,
# and restart only the application that this script stopped.
# Usage: mailclient_backup_with_restart <auto|betterbird|thunderbird> <user> <archive> <profile> [auto|flatpak|native]

_mailclient_error() { printf 'ERROR: %s\n' "$*" >&2; }

_mailclient_user_command() {
    local user="$1" uid="$2"
    shift 2
    # runuser only works for privileged callers; interactive use as the target
    # user must execute Flatpak commands directly.
    if (( EUID == uid )); then
        env "XDG_RUNTIME_DIR=/run/user/$uid" \
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus" "$@"
    elif (( EUID == 0 )); then
        runuser -u "$user" -- env \
            "XDG_RUNTIME_DIR=/run/user/$uid" \
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus" "$@"
    else
        _mailclient_error "Run as $user or root (current UID: $EUID)."
        return 1
    fi
}

_mailclient_app_id() {
    case "$1" in
        betterbird) printf '%s\n' eu.betterbird.Betterbird ;;
        thunderbird) printf '%s\n' org.mozilla.Thunderbird ;;
        *) return 1 ;;
    esac
}

_mailclient_profile_hint() {
    case "$1" in
        */.var/app/eu.betterbird.Betterbird/*) printf 'betterbird flatpak\n' ;;
        */.var/app/org.mozilla.Thunderbird/*) printf 'thunderbird flatpak\n' ;;
        *) printf 'unknown native\n' ;;
    esac
}

_mailclient_first_arg() {
    local pid="$1" first
    [[ -r "/proc/$pid/cmdline" ]] || return 1
    IFS= read -r -d '' first < "/proc/$pid/cmdline" || return 1
    printf '%s\n' "$first"
}

_mailclient_has_child_flags() {
    local pid="$1" arg
    [[ -r "/proc/$pid/cmdline" ]] || return 1
    while IFS= read -r -d '' arg; do
        case "$arg" in
            -contentproc|-parentBuildID|--type=*|-isForBrowser) return 0 ;;
        esac
    done < "/proc/$pid/cmdline"
    return 1
}

_mailclient_is_flatpak_process() {
    local pid="$1" first="$2"
    [[ "$first" == /app/* ]] && return 0
    [[ -r "/proc/$pid/root/.flatpak-info" ]]
}

# Print distinct main application processes as: client<TAB>mode<TAB>PID.
# Crucial: `flatpak ps --columns=...,child-pid` often reports a bwrap PID,
# not the real Betterbird/Thunderbird main process. Inspect real argv[0]
# (which may be /app/lib/betterbird/betterbird even if comm is MainThread).
_mailclient_instances() {
    local user="$1" uid="$2" pid first client mode app flatpak_pid
    local flatpak_output='' proc_list=''
    local -A seen=() actual_count=() reported_count=()

    # pgrep -f matches the full command line (unlike pgrep -x, which may miss
    # Mozilla's renamed process). Verify argv[0] so that bwrap, shells,
    # helpers and content processes do not count as extra app instances.
    proc_list="$(pgrep -u "$uid" -f 'betterbird|thunderbird' 2>/dev/null || :)"
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        first="$(_mailclient_first_arg "$pid" 2>/dev/null)" || continue
        case "$first" in
            betterbird|*/betterbird|betterbird-bin|*/betterbird-bin) client=betterbird ;;
            thunderbird|*/thunderbird|thunderbird-bin|*/thunderbird-bin) client=thunderbird ;;
            *) continue ;;
        esac
        if [[ "$first" == *-bin ]] && _mailclient_has_child_flags "$pid"; then
            continue
        fi
        if _mailclient_is_flatpak_process "$pid" "$first"; then
            mode=flatpak
            actual_count["$client"]=$(( ${actual_count[$client]:-0} + 1 ))
        else
            mode=native
        fi
        [[ -n "${seen[$pid]:-}" ]] && continue
        seen["$pid"]=1
        printf '%s\t%s\t%s\n' "$client" "$mode" "$pid"
    done <<< "$proc_list"

    # This is a fallback when no identifiable application main process was
    # found. It also handles installations whose process name is unusual.
    # Check in the target user's session, not only in the root cron context.
    if command -v flatpak >/dev/null 2>&1; then
        flatpak_output="$(_mailclient_user_command "$user" "$uid" flatpak ps \
            --columns=application,pid,child-pid 2>/dev/null || :)"
        if [[ -z "$flatpak_output" ]] && (( EUID == uid )); then
            flatpak_output="$(flatpak ps --columns=application,pid,child-pid 2>/dev/null || :)"
        fi
        while read -r app pid flatpak_pid; do
            [[ "$pid" =~ ^[0-9]+$ && "$flatpak_pid" =~ ^[0-9]+$ ]] || continue
            case "$app" in
                eu.betterbird.Betterbird) client=betterbird ;;
                org.mozilla.Thunderbird) client=thunderbird ;;
                *) continue ;;
            esac
            # Prefer real main PIDs, but retain unmatched Flatpak instances.
            # Two sandboxes with only one identifiable main process must
            # not silently be treated as one safe instance.
            reported_count["$client"]=$(( ${reported_count[$client]:-0} + 1 ))
            (( ${reported_count[$client]} <= ${actual_count[$client]:-0} )) && continue
            [[ -n "${seen[$flatpak_pid]:-}" ]] && continue
            seen["$flatpak_pid"]=1
            printf '%s\tflatpak\t%s\n' "$client" "$flatpak_pid"
        done <<< "$flatpak_output"
    fi
}

_mailclient_profile_from_args() {
    local pid="$1" arg previous='' value
    [[ -r "/proc/$pid/cmdline" ]] || return 1
    while IFS= read -r -d '' arg; do
        case "$previous" in
            -profile|--profile) printf '%s\n' "$arg"; return 0 ;;
        esac
        case "$arg" in
            -profile|--profile) previous="$arg" ;;
            -profile=*|--profile=*) value="${arg#*=}"; printf '%s\n' "$value"; return 0 ;;
            *) previous='' ;;
        esac
    done < "/proc/$pid/cmdline"
    return 1
}

_mailclient_restore_env() {
    local pid="$1" item
    MAILCLIENT_SESSION_ENV=()
    [[ -r "/proc/$pid/environ" ]] || return 1
    while IFS= read -r -d '' item; do
        case "$item" in
            DISPLAY=*|WAYLAND_DISPLAY=*|XAUTHORITY=*|XDG_SESSION_TYPE=*|XDG_CURRENT_DESKTOP=*|XDG_SESSION_DESKTOP=*)
                MAILCLIENT_SESSION_ENV+=("$item") ;;
        esac
    done < "/proc/$pid/environ"
}

_mailclient_any_instance() {
    local user="$1" uid="$2" wanted_client="$3" wanted_mode="$4"
    local client mode pid
    while IFS=$'\t' read -r client mode pid; do
        if [[ "$client" == "$wanted_client" && "$mode" == "$wanted_mode" ]]; then
            return 0
        fi
    done < <(_mailclient_instances "$user" "$uid")
    return 1
}

_mailclient_restart() {
    local user="$1" uid="$2" client="$3" mode="$4" app_id="$5" launcher_path="$6" profile="$7" explicit="$8"
    local -a launcher=()
    local n

    if [[ ! -S "/run/user/$uid/bus" ]]; then
        _mailclient_error "Graphical user session unavailable; cannot restart $client."
        return 1
    fi
    if [[ "$mode" == flatpak ]]; then
        launcher=(flatpak run "$app_id")
    elif [[ -n "$launcher_path" && -x "$launcher_path" ]]; then
        launcher=("$launcher_path")
    elif command -v "$client" >/dev/null 2>&1; then
        launcher=("$client")
    else
        _mailclient_error "Native launcher not found for $client."
        return 1
    fi
    if [[ "$explicit" == 1 ]]; then
        launcher+=(-profile "$profile")
    fi

    printf 'Restarting %s (%s) as %s\n' "$client" "$mode" "$user"
    _mailclient_user_command "$user" "$uid" "${MAILCLIENT_SESSION_ENV[@]}" \
        bash -c 'nohup "$@" </dev/null >/dev/null 2>&1 &' _ "${launcher[@]}" || return 1
    for ((n=0; n<15; n++)); do
        sleep 1
        if _mailclient_any_instance "$user" "$uid" "$client" "$mode"; then
            printf 'Mail client restarted.\n'
            return 0
        fi
    done
    _mailclient_error 'Could not verify mail-client restart.'
    return 1
}

# Also used by betterbird-backup.sh when both scripts are sourced.
_mailclient_profile_running() {
    local profile="$1" owner uid hint_client hint_mode client mode pid
    # A new restore destination cannot be held open as an existing profile.
    [[ -d "$profile" ]] || return 1
    owner="$(stat -c %U -- "$profile")" || return 2
    uid="$(id -u "$owner")" || return 2
    command -v pgrep >/dev/null 2>&1 || return 2
    [[ -r /proc/$$/cmdline ]] || return 2
    read -r hint_client hint_mode < <(_mailclient_profile_hint "$profile")
    while IFS=$'\t' read -r client mode pid; do
        if [[ "$hint_client" == unknown || ( "$client" == "$hint_client" && "$mode" == "$hint_mode" ) ]]; then
            return 0
        fi
    done < <(_mailclient_instances "$owner" "$uid")
    return 1
}

mailclient_backup_with_restart() {
    if (( $# < 4 || $# > 5 )); then
        _mailclient_error 'Usage: mailclient_backup_with_restart <auto|betterbird|thunderbird> <user> <archive> <profile> [auto|flatpak|native]'
        return 2
    fi
    local requested_client="$1" user="$2" archive="$3" profile="$4" requested_mode="${5:-auto}"
    local uid hint_client hint_mode client mode pid process_profile
    local chosen_client='' chosen_mode='' chosen_pid='' explicit=0 launcher_path='' app_id
    local -a compatible=() conflicts=()
    local stopped=0 backup_status=0 restart_status=0 n

    case "$requested_client" in auto|betterbird|thunderbird) ;; *) _mailclient_error 'Invalid client.'; return 2 ;; esac
    case "$requested_mode" in auto|flatpak|native) ;; *) _mailclient_error 'Invalid installation mode.'; return 2 ;; esac
    [[ -d "$profile" ]] || { _mailclient_error "Profile not found: $profile"; return 1; }
    profile="$(realpath -e -- "$profile")" || return 1
    uid="$(id -u "$user")" || return 1
    if ! command -v pgrep >/dev/null 2>&1 || [[ ! -r /proc/$$/cmdline ]]; then
        _mailclient_error 'Cannot inspect running processes; refusing to back up a potentially live profile.'
        return 1
    fi
    read -r hint_client hint_mode < <(_mailclient_profile_hint "$profile")
    if (( EUID != uid && EUID != 0 )); then
        _mailclient_error "Run as $user or root."
        return 1
    fi

    while IFS=$'\t' read -r client mode pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        [[ "$requested_client" == auto || "$client" == "$requested_client" ]] || continue
        [[ "$requested_mode" == auto || "$mode" == "$requested_mode" ]] || continue
        process_profile="$(_mailclient_profile_from_args "$pid" 2>/dev/null || :)"
        if [[ -n "$process_profile" ]]; then
            process_profile="$(realpath -m -- "$process_profile")"
            if [[ "$process_profile" != "$profile" ]]; then
                conflicts+=("$client/$mode PID $pid uses $process_profile")
                continue
            fi
        fi
        if [[ "$hint_mode" == flatpak && ( "$client" != "$hint_client" || "$mode" != flatpak ) ]]; then
            conflicts+=("$client/$mode PID $pid does not match profile")
            continue
        fi
        compatible+=("$client"$'\t'"$mode"$'\t'"$pid"$'\t'"${process_profile:+1}")
    done < <(_mailclient_instances "$user" "$uid")

    if (( ${#compatible[@]} > 1 )); then
        _mailclient_error 'Multiple possible mail-client processes; refusing to choose an arbitrary profile.'
        printf '  %s\n' "${compatible[@]}" >&2
        return 1
    fi
    if (( ${#compatible[@]} == 1 )); then
        IFS=$'\t' read -r chosen_client chosen_mode chosen_pid explicit <<< "${compatible[0]}"
        explicit="${explicit:-0}"
        if (( ${#conflicts[@]} > 0 )) && [[ "$explicit" != 1 ]]; then
            _mailclient_error 'Multiple incompatible instances are running; cannot associate profile safely.'
            printf '  %s\n' "${conflicts[@]}" >&2
            return 1
        fi
    else
        if (( ${#conflicts[@]} > 0 )); then
            _mailclient_error 'Mail-client process is running with a different profile.'
            printf '  %s\n' "${conflicts[@]}" >&2
            return 1
        fi
        chosen_client="$requested_client"
        chosen_mode="$requested_mode"
        [[ "$chosen_client" != auto ]] || chosen_client="$hint_client"
        [[ "$chosen_mode" != auto ]] || chosen_mode="$hint_mode"
        if [[ "$chosen_client" == unknown ]]; then
            _mailclient_error 'Cannot identify the client from an unused native profile. Specify betterbird or thunderbird.'
            return 1
        fi
    fi
    if [[ "$hint_mode" == flatpak && ( "$chosen_client" != "$hint_client" || "$chosen_mode" != flatpak ) ]]; then
        _mailclient_error 'Client or installation mode does not match Flatpak profile path.'
        return 1
    fi
    app_id="$(_mailclient_app_id "$chosen_client")" || return 1
    printf 'Detected: %s (%s), user %s, profile %s\n' "$chosen_client" "$chosen_mode" "$user" "$profile"

    if [[ -n "$chosen_pid" ]]; then
        _mailclient_restore_env "$chosen_pid" || printf 'WARNING: Could not capture the original GUI environment.\n' >&2
        if [[ "$chosen_mode" == native ]]; then
            launcher_path="$(readlink -f -- "/proc/$chosen_pid/exe" 2>/dev/null || :)"
        fi
        printf 'Stopping %s PID %s (SIGTERM)\n' "$chosen_client" "$chosen_pid"
        kill -TERM "$chosen_pid" || return 1
        for ((n=0; n<10; n++)); do
            sleep 1
            if ! _mailclient_any_instance "$user" "$uid" "$chosen_client" "$chosen_mode"; then
                stopped=1
                break
            fi
        done
        if (( !stopped )) && [[ "$chosen_mode" == flatpak ]]; then
            # This is an ungraceful fallback. It may lose unsaved drafts.
            printf 'WARNING: SIGTERM did not close Flatpak. Using flatpak kill (unsaved changes may be lost).\n' >&2
            _mailclient_user_command "$user" "$uid" flatpak kill "$app_id" || {
                _mailclient_error 'Flatpak kill failed; backup skipped.'
                return 1
            }
        fi
        if (( !stopped )); then
            for ((n=0; n<20; n++)); do
                sleep 1
                if ! _mailclient_any_instance "$user" "$uid" "$chosen_client" "$chosen_mode"; then
                    stopped=1
                    break
                fi
            done
        fi
        if (( !stopped )); then
            _mailclient_error 'Mail client did not stop; backup skipped.'
            return 1
        fi
        printf 'Mail client stopped.\n'
    else
        printf 'Client not running. No restart will be attempted.\n'
    fi

    # The exporter performs its own safety check. Both scripts now use the
    # same instance detector whenever they are loaded together.
    betterbird_export_settings "$archive" "$profile" || backup_status=$?
    if (( stopped )); then
        _mailclient_restart "$user" "$uid" "$chosen_client" "$chosen_mode" "$app_id" "$launcher_path" "$profile" "$explicit" || restart_status=$?
    fi
    if (( backup_status != 0 )); then
        _mailclient_error "Backup failed (exit code $backup_status)."
        return "$backup_status"
    fi
    return "$restart_status"
}
