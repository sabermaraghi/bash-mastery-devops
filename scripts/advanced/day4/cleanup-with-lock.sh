#!/bin/bash
set -euo pipefail

LOCK="/tmp/cleanup.lock"
MAX_AGE=7

acquire_lock() {
  if ! mkdir "$LOCK" 2>/dev/null; then
    echo "ERROR: Script is already running" >&2
    exit 1
  fi
}
release_lock() { rmdir "$LOCK"; }

trap release_lock EXIT
acquire_lock

echo "Deleting files older than $MAX_AGE days..."
find /tmp -type f -name "*.tmp" -mtime +$MAX_AGE -print -delete

echo "Cleanup completed"
