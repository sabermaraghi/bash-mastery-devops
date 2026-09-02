#!/usr/bin/env bash
# A real module composed entirely from shared /lib building blocks.
# Demonstrates the payoff of Day 11-13: no logger, retry, or validator is
# re-implemented here — they're sourced once from /lib.
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/retry.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"

export COMPONENT="backup-manager"

backup() {
  local src="$1" dest="$2"
  require_var src dest || return 1
  require_safe_path "$src" || return 1
  require_dir "$src" || return 1
  mkdir -p "$dest"
  local archive="$dest/backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  retry 3 1 tar -czf "$archive" -C "$(dirname "$src")" "$(basename "$src")"
  log_info "backup complete: $archive"
  echo "$archive"
}

# Only run when executed directly, not when sourced by a test.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  backup "${1:-/tmp}" "${2:-/tmp/backups}"
fi
