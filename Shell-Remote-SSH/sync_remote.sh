#!/usr/bin/env bash

# Bash helper for synchronizing directories and uploading files over SSH.
# Requires rsync on the local computer and the remote server.

_sync_remote_error() {
    printf 'ERROR: %s\n' "$*" >&2
}

_sync_remote_config() {
    local -n host_ref="$1"
    local -n root_ref="$2"
    local -n user_ref="$3"

    host_ref="${SYNC_REMOTE_HOST:-}"
    root_ref="${SYNC_REMOTE_ROOT:-}"
    user_ref="${SYNC_REMOTE_USER:-}"

    if [[ -z "$host_ref" || -z "$root_ref" || -z "$user_ref" ]]; then
        _sync_remote_error 'Set SYNC_REMOTE_HOST, SYNC_REMOTE_ROOT and SYNC_REMOTE_USER.'
        return 1
    fi

    # Restrict remote values to shell-safe characters.
    if [[ ! "$host_ref" =~ ^[a-zA-Z0-9._-]+$ ||
          ! "$user_ref" =~ ^[a-zA-Z0-9._-]+$ ||
          ! "$root_ref" =~ ^/[a-zA-Z0-9._/-]+$ ||
          "$root_ref" == *'//'* ]]; then
        _sync_remote_error 'Invalid remote SSH configuration.'
        return 1
    fi

    root_ref="${root_ref%/}"
    if [[ -z "$root_ref" || "$root_ref" == '/' ||
          "/${root_ref#/}/" == *'/../'* ||
          "/${root_ref#/}/" == *'/./'* ]]; then
        _sync_remote_error 'SYNC_REMOTE_ROOT must be a safe absolute directory (not /).'
        return 1
    fi
}

_sync_remote_relative_path() {
    local path="$1"
    if [[ -z "$path" || "$path" == /* || "$path" == *'//'* ||
          ! "$path" =~ ^[a-zA-Z0-9._/-]+$ ||
          "/$path/" == *'/../'* || "/$path/" == *'/./'* ]]; then
        _sync_remote_error "Invalid relative remote path: $path"
        return 1
    fi
}

_sync_remote_directory_impl() {
    local dry_run="$1"
    local local_dir="$2"
    local remote_directory="$3"
    shift 3
    local excludes=("$@")

    local remote_host remote_root remote_user
    _sync_remote_config remote_host remote_root remote_user || return 1
    _sync_remote_relative_path "$remote_directory" || return 1

    if [[ ! -d "$local_dir" ]]; then
        _sync_remote_error "Local directory does not exist: $local_dir"
        return 1
    fi

    local remote_dir="${remote_root}/${remote_directory%/}"
    local destination="${remote_user}@${remote_host}:${remote_dir}/"
    local args=(--archive --verbose --human-readable --itemize-changes --delete)
    local pattern
    for pattern in "${excludes[@]}"; do
        args+=(--exclude="$pattern")
    done

    if [[ "$dry_run" == 'true' ]]; then
        args+=(--dry-run)
        printf 'Preview (no files will be changed): %s/ -> %s\n' "${local_dir%/}" "$destination"
    else
        printf 'Synchronizing: %s/ -> %s\n' "${local_dir%/}" "$destination"
        if ! ssh -l "$remote_user" "$remote_host" "mkdir -p -- '$remote_dir'"; then
            _sync_remote_error "Could not create remote directory: $remote_dir"
            return 1
        fi
    fi

    rsync "${args[@]}" -- "${local_dir%/}/" "$destination"
    local exit_code=$?
    if (( exit_code != 0 )); then
        _sync_remote_error "Rsync failed (exit code $exit_code)."
        return "$exit_code"
    fi

    if [[ "$dry_run" == 'true' ]]; then
        printf 'Preview completed. No files were changed.\n'
    else
        printf 'Remote synchronization completed.\n'
    fi
}

# Synchronize a directory relative to SYNC_REMOTE_SOURCE_ROOT.
# Usage: sync_remote [--dry-run] <directory-name> [exclude-pattern ...]
sync_remote() {
    local dry_run=false
    if [[ "${1:-}" == '--dry-run' ]]; then
        dry_run=true
        shift
    fi

    local directory_name="${1:-}"
    if [[ -z "$directory_name" || "$directory_name" == '.' ||
          "$directory_name" == '..' || "$directory_name" == */* ||
          ! "$directory_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        _sync_remote_error 'Usage: sync_remote [--dry-run] <directory-name> [exclude-pattern ...]'
        return 1
    fi
    shift

    local script_dir source_root
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    source_root="${SYNC_REMOTE_SOURCE_ROOT:-${script_dir}/../..}"
    if [[ ! -d "$source_root" ]]; then
        _sync_remote_error "Source root does not exist: $source_root"
        return 1
    fi
    source_root="$(cd -- "$source_root" && pwd -P)" || return 1

    local local_dir="${source_root}/${directory_name}"
    if [[ ! -d "$local_dir" ]]; then
        _sync_remote_error "Source directory does not exist: $local_dir"
        return 1
    fi

    if [[ "$dry_run" == 'true' ]]; then
        _sync_remote_directory_impl true "$local_dir" "$directory_name" "$@"
        return $?
    fi

    _sync_remote_directory_impl false "$local_dir" "$directory_name" "$@" || return $?

    # Optional success marker, relative to SYNC_REMOTE_ROOT.
    if [[ -n "${SYNC_REMOTE_TOUCH_FILE:-}" ]]; then
        local remote_host remote_root remote_user
        _sync_remote_config remote_host remote_root remote_user || return 1
        _sync_remote_relative_path "$SYNC_REMOTE_TOUCH_FILE" || return 1
        local marker="${remote_root}/${SYNC_REMOTE_TOUCH_FILE}"
        if ! ssh -l "$remote_user" "$remote_host" "touch -- '$marker'"; then
            _sync_remote_error "Could not update success marker: $marker"
            return 1
        fi
    fi
}

# Preview directory synchronization without changing or deleting remote files.
# Usage: sync_remote_preview <local-directory> <remote-relative-directory> [exclude-pattern ...]
sync_remote_preview() {
    if (( $# < 2 )); then
        _sync_remote_error 'Usage: sync_remote_preview <local-directory> <remote-relative-directory> [exclude-pattern ...]'
        return 1
    fi
    _sync_remote_directory_impl true "$@"
}

# Actually synchronize any local directory to a relative remote directory.
# CAUTION: Deletes remote files that are absent locally (unless excluded).
# Usage: sync_remote_directory <local-directory> <remote-relative-directory> [exclude-pattern ...]
sync_remote_directory() {
    if (( $# < 2 )); then
        _sync_remote_error 'Usage: sync_remote_directory <local-directory> <remote-relative-directory> [exclude-pattern ...]'
        return 1
    fi
    _sync_remote_directory_impl false "$@"
}

# Upload one local file to a path relative to SYNC_REMOTE_ROOT.
# Usage: upload_remote_file <local-file> <remote-relative-file>
upload_remote_file() {
    if (( $# != 2 )); then
        _sync_remote_error 'Usage: upload_remote_file <local-file> <remote-relative-file>'
        return 1
    fi
    local local_file="$1"
    local remote_file="$2"
    if [[ ! -f "$local_file" ]]; then
        _sync_remote_error "Local file does not exist: $local_file"
        return 1
    fi

    local remote_host remote_root remote_user
    _sync_remote_config remote_host remote_root remote_user || return 1
    _sync_remote_relative_path "$remote_file" || return 1
    if [[ "$remote_file" == */ ]]; then
        _sync_remote_error 'Remote file must not end in a slash.'
        return 1
    fi

    local remote_path="${remote_root}/${remote_file}"
    local remote_dir="${remote_path%/*}"
    if ! ssh -l "$remote_user" "$remote_host" "mkdir -p -- '$remote_dir'"; then
        _sync_remote_error "Could not create remote directory: $remote_dir"
        return 1
    fi

    printf 'Uploading: %s -> %s@%s:%s\n' "$local_file" "$remote_user" "$remote_host" "$remote_path"
    rsync --archive --verbose --human-readable --itemize-changes -- \
        "$local_file" "${remote_user}@${remote_host}:${remote_path}"
    local exit_code=$?
    if (( exit_code != 0 )); then
        _sync_remote_error "Upload failed (exit code $exit_code)."
        return "$exit_code"
    fi
    printf 'File uploaded successfully.\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    sync_remote "$@"
fi
