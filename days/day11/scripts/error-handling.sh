#!/usr/bin/env bash
# The safe-scripting toolkit: strict mode, traps, and shared logging.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day11-demo.log}" COMPONENT="day11"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"

cleanup() { log_info "cleanup ran (exit code $?)"; }
trap cleanup EXIT
trap 'log_error "failed at line $LINENO"' ERR

log_info "starting work"

risky() {
  local n="$1"
  if ((n < 0)); then
    log_error "negative input: $n"
    return 1
  fi
  echo $((n * 2))
}

if result=$(risky 21); then
  log_info "risky(21) = $result"
fi

# Handle an expected failure without aborting the whole script.
if ! risky -5 2>/dev/null; then
  log_warn "risky(-5) rejected as expected"
fi

log_info "done"
