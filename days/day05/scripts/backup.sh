#!/usr/bin/env bash
# A small, real backup script driven entirely by its arguments.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 SOURCE_DIR [DEST_DIR]" >&2
  exit 1
fi

src="$1"
dest="${2:-./backups}"

if [[ ! -d "$src" ]]; then
  echo "Source directory not found: $src" >&2
  exit 1
fi

mkdir -p "$dest"
archive="$dest/backup-$(basename "$src")-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$archive" -C "$(dirname "$src")" "$(basename "$src")"
echo "Created archive: $archive"
