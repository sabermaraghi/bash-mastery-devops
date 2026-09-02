#!/usr/bin/env bash
set -euo pipefail

DB="mydb"
DB_USER="postgres"
BACKUP_DIR="/backup/db"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${DB}-${DATE}.sql.gz"
LOCKFILE="/tmp/.db-backup-in-progress"

log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DB] [$level] $*" | tee -a /var/log/db-backup.log
}

command -v pg_dump &>/dev/null || {
  log "ERROR" "pg_dump is not installed"
  exit 1
}

if [[ -f "$LOCKFILE" ]]; then
  log "ERROR" "Backup already in progress"
  exit 1
fi
touch "$LOCKFILE"

trap 'log "ERROR" "Backup failed at line $LINENO"; exit 1' ERR
trap 'rm -f "$LOCKFILE"' EXIT

log "INFO" "Starting backup of $DB"
mkdir -p "$BACKUP_DIR"

pg_dump -U "$DB_USER" "$DB" | gzip >"$BACKUP_FILE"

# verify
if zcat "$BACKUP_FILE" | head -10 >/dev/null; then
  log "SUCCESS" "Backup successful: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
  ln -sf "$BACKUP_FILE" "$BACKUP_DIR/${DB}-latest.sql.gz"
else
  log "ERROR" "Backup is corrupted"
  rm -f "$BACKUP_FILE"
  exit 1
fi
