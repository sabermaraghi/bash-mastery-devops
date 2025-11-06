#!/bin/bash
set -euo pipefail

backup_dir() {
  local source="$1"
  local dest="$2"
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_name="$(basename "$source")_$timestamp.tar.gz"

  echo "Backing up $source → $dest/$backup_name"
  tar -czf "$dest/$backup_name" "$source"
  echo "Done! Backup created."
}

# Default values
SRC="${1:-$HOME/documents}"
DEST="${2:-/tmp/backups}"

mkdir -p "$DEST"
backup_dir "$SRC" "$DEST"

# ./scripts/projects/day2-backup.sh ~/docs /backup
