#!/bin/bash
set -euo pipefail

BACKUP_DIR="./backup/daily"
DAYS=30
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true ;;
    --days) DAYS="$2"; shift ;;
  esac
  shift
done

echo "Cleaning backups older than $DAYS days in $BACKUP_DIR"

if $DRY_RUN; then
  find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$DAYS -print
else
  find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$DAYS -exec rm -v {} \;
  echo "Cleanup completed."
fi
