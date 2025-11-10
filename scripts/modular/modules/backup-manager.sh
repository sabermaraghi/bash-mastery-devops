#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s inherit_errexit 2>/dev/null || true

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/retry.sh"
source "$SCRIPT_DIR/../lib/lock.sh"

COMPONENT="backup-manager"
acquire_lock

BACKUP_DIR="/backup/data"
SRC="/var/www"

log_info "Starting backup of $SRC"

do_backup() {
  rsync -av --delete "$SRC/" "$BACKUP_DIR/$(date +%Y%m%d-%H%M%S)/"
}

retry 3 5 do_backup

log_info "Backup completed successfully"
