#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SOURCE="$1"
ENCRYPTION="$2"
RECIPIENT="$3"
RETENTION_DAYS="$4"

readonly BACKUP_DIR="/backups"
readonly LOG_FILE="/var/log/backup-orchestrator.log"
readonly LOCK_FILE="/var/run/backup-orchestrator.lock"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [BACKUP] $*" | tee -a "$LOG_FILE"
}

acquire_lock() {
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    log "ERROR: Another backup is running"
    exit 1
  fi
  echo $$ >&200
}

cleanup_old() {
  log "Cleaning backups older than $RETENTION_DAYS days"
  find "$BACKUP_DIR" -name "*.tar.gz*" -mtime +"$RETENTION_DAYS" -delete
}

acquire_lock
trap 'flock -u 200; rm -f "$LOCK_FILE"' EXIT

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_FILE="$BACKUP_DIR/backup-$TIMESTAMP.tar.gz"
ENCRYPTED_FILE="$BACKUP_FILE.enc"

mkdir -p "$BACKUP_DIR"

log "Starting backup: $SOURCE -> $BACKUP_FILE"

if [[ ! -d "$SOURCE" ]]; then
  log "ERROR: Source directory not found: $SOURCE"
  exit 1
fi

tar -czf - "$SOURCE" 2>/dev/null | {
  if [[ "$ENCRYPTION" == "gpg" && -n "$RECIPIENT" ]]; then
    gpg --batch --trust-model always --encrypt --recipient "$RECIPIENT"
  else
    cat
  fi
} > "${ENCRYPTION:+$ENCRYPTED_FILE}"

FINAL_FILE="${ENCRYPTION:+$ENCRYPTED_FILE}"
FINAL_FILE="${FINAL_FILE:-$BACKUP_FILE}"

log "Backup completed: $FINAL_FILE"
cleanup_old

echo "$FINAL_FILE"
