#!/bin/bash
set -euo pipefail

DB="mydb"
USER="postgres"
BACKUP_DIR="/backup/db"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${DB}-${DATE}.sql.gz"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DB] $*" | tee -a /var/log/db-backup.log; }

trap 'log "ERROR" "Backup failed at line $LINENO"; exit 1' ERR
trap 'log "INFO" "Temporary cleanup"; rm -f /tmp/.backup-in-progress' EXIT

touch /tmp/.backup-in-progress

log "INFO" "Starting backup of $DB"
mkdir -p "$BACKUP_DIR"

pg_dump -U "$USER" "$DB" | gzip > "$BACKUP_FILE"

# verify
if zcat "$BACKUP_FILE" | head -10 >/dev/null; then
  log "SUCCESS" "Backup successful: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
  ln -sf "$BACKUP_FILE" "$BACKUP_DIR/${DB}-latest.sql.gz"
else
  log "ERROR" "Backup is corrupted"
  rm -f "$BACKUP_FILE"
  exit 1
fi
