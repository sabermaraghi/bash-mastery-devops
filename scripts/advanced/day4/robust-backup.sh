#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

LOG="/var/log/robust-backup.log"
LOCK="/tmp/robust-backup.lock"
SRC="/home"
DEST="/backup/home-$(date +%Y%m%d-%H%M%S)"
ROLLBACK="/backup/last-successful"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

cleanup() {
  rm -f "$LOCK"
  log "INFO" "Cleanup completed"
}
trap cleanup EXIT

trap 'log "ERROR" "Error at line $LINENO"; exit 1' ERR

if [[ -f "$LOCK" ]]; then
  log "ERROR" "Script is already running (lock file exists)"
  exit 1
fi
touch "$LOCK"

log "INFO" "Starting backup from $SRC"

mkdir -p "$DEST"
rsync -av --delete "$SRC/" "$DEST/" | tee -a "$LOG"

# rollback link
rm -f "$ROLLBACK"
ln -s "$DEST" "$ROLLBACK"

log "SUCCESS" "Backup successfully saved in $DEST"
log "INFO" "rollback link: $ROLLBACK"
