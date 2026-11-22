# Remote SSH / rsync Helper

[![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)

**🇬🇧 English** | [🇩🇪 Deutsch](README.de.md)

A reusable **Bash helper for uploading files and synchronizing directories with a remote Linux server** using `rsync` over SSH. Source it from other shell scripts, or run it directly to deploy a named project directory.

> **Protocol note:** This script uses **rsync over SSH**, not the SFTP protocol. Both can use SSH for secure transport, but `rsync` must also be installed on the remote server.

## Features

- Upload an individual file, creating its remote parent directory if necessary.
- Synchronize a directory, transferring only changes.
- **Preview** directory synchronization with `--dry-run`, without changing remote files.
- Exclude files or directories using rsync patterns.
- Optionally update a remote success-marker file after a successful project synchronization.
- Return non-zero exit codes on errors for integration into automation scripts.
- Reject unsafe remote relative paths and validate the configured remote root.

## Requirements

- Bash 4.3 or newer (uses `local -n`).
- `rsync` installed **both locally and on the remote server**.
- OpenSSH client (`ssh`) locally and SSH access to the remote server.
- Sufficient permissions to create directories and upload files within the remote root.

For unattended deployments, SSH key authentication is recommended.

## Installation

Copy `sync_remote.sh` into your project, for example:

```text
my-project/
├── scripts/
│   ├── sync_remote.sh
│   └── deploy.sh
└── dist/
```

Load the functions in `deploy.sh`:

```bash
#!/usr/bin/env bash
set -e

source "$(dirname "${BASH_SOURCE[0]}")/sync_remote.sh"
```

## Configuration

Set these environment variables **before** calling the functions:

| Variable                  | Required | Description                                                                                  |
| ------------------------- | -------- | -------------------------------------------------------------------------------------------- |
| `SYNC_REMOTE_HOST`        | Yes      | SSH hostname or IP address                                                                   |
| `SYNC_REMOTE_USER`        | Yes      | Remote SSH username                                                                          |
| `SYNC_REMOTE_ROOT`        | Yes      | Absolute deployment root on the server; cannot be `/`                                        |
| `SYNC_REMOTE_SOURCE_ROOT` | No       | Local parent directory for `sync_remote`; defaults to two directories above `sync_remote.sh` |
| `SYNC_REMOTE_TOUCH_FILE`  | No       | Relative path of a file to update with `touch` after a successful `sync_remote` deployment   |

Example:

```bash
export SYNC_REMOTE_HOST="example.com"
export SYNC_REMOTE_USER="deploy"
export SYNC_REMOTE_ROOT="/var/www/sites"
export SYNC_REMOTE_SOURCE_ROOT="$HOME/projects"
# Optional: the parent directory must already exist on the server.
export SYNC_REMOTE_TOUCH_FILE="website/public/deploy-success.txt"
```

Remote paths are intentionally limited to letters, numbers, dots, underscores, hyphens and slashes. They cannot contain `.` or `..` as whole path components. Remote paths containing spaces are not supported.

## Usage

### 1. Synchronize a project directory

```bash
sync_remote "website"
```

With the configuration above, this synchronizes:

```text
$HOME/projects/website/  ->  deploy@example.com:/var/www/sites/website/
```

Exclude files or directories:

```bash
sync_remote "website" ".git/" "node_modules/" "*.log"
```

Preview the changes first:

```bash
sync_remote --dry-run "website" ".git/" "node_modules/"
```

You can also execute the helper directly (after `chmod +x sync_remote.sh`):

```bash
./sync_remote.sh --dry-run website
./sync_remote.sh website
```

### 2. Preview an arbitrary directory

```bash
sync_remote_preview "./dist" "website/public" "*.map"
```

This shows the changes `rsync` would make, **without uploading or deleting anything**. The remote destination or its parent may need to exist for preview to work.

### 3. Synchronize an arbitrary directory

```bash
sync_remote_directory "./dist" "website/public" "*.map"
```

Creates the destination if necessary, then performs the synchronization.

### 4. Upload a single file

```bash
upload_remote_file "./config/app.json" "website/config/app.json"
```

Creates the remote parent directory if necessary. Existing files at the destination may be overwritten.

## Example deployment script

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/sync_remote.sh"

export SYNC_REMOTE_HOST="example.com"
export SYNC_REMOTE_USER="deploy"
export SYNC_REMOTE_ROOT="/var/www/sites"
export SYNC_REMOTE_SOURCE_ROOT="$HOME/projects"

sync_remote --dry-run "website" ".git/" "node_modules/"

# Review the output before enabling the actual deployment:
# sync_remote "website" ".git/" "node_modules/"
```

## ⚠️ Important: deletions and security

- `sync_remote` and `sync_remote_directory` use **`rsync --delete`**. Files present at the destination but absent from the local source **will be deleted**, except for paths protected by applicable rsync exclude rules. Always start with a preview and verify the source and target paths.
- `sync_remote_preview` and `sync_remote --dry-run` **never modify remote files**.
- Exclude patterns use rsync matching semantics. They are not a comprehensive safeguard against an incorrect destination.
- The script does not provide a backup or rollback mechanism.
- Do not commit passwords or private SSH keys into your repository. Grant the deployment account access only to the necessary directories.
- `SYNC_REMOTE_TOUCH_FILE` is **only** used by `sync_remote` after an actual successful synchronization. Its parent directory must already exist.
- Local paths can contain spaces; remote path components intentionally cannot.

## Return codes

Each helper function returns `0` on success or a non-zero status on failure. Where possible, failed `rsync` operations propagate their original exit code.

```bash
if ! upload_remote_file "./build/index.html" "website/index.html"; then
    echo "Deployment failed" >&2
    exit 1
fi
```

## AI-assisted development

These scripts and their documentation were created in part with the assistance of artificial intelligence (AI), including ChatGPT. AI-assisted code is not a guarantee of correctness. Review and test the scripts for your own use case, especially before relying on automated backups or restores.
