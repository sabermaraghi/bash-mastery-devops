#!/usr/bin/env bash
# context-guard.sh — assert you're pointed at the intended cluster.
#
# Read-only guard to put in front of any destructive automation:
#   context-guard.sh staging-cluster && ./do-risky-thing.sh
# Exits 0 when the current kube context matches EXPECTED, non-zero otherwise.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day25-guard.log}" COMPONENT="context-guard"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/kubectl-lib.sh"

main() {
  local expected="${1:-}"
  [[ -n "$expected" ]] || {
    echo "usage: $0 EXPECTED_CONTEXT" >&2
    exit 2
  }

  local current
  current="$(current_context)" || true
  if [[ -z "$current" ]]; then
    log_error "could not determine current context (is a cluster configured?)"
    return 1
  fi

  if [[ "$current" == "$expected" ]]; then
    echo "context OK: $current"
    return 0
  fi

  echo "context MISMATCH: current='$current' expected='$expected'" >&2
  log_error "context guard blocked: current=$current expected=$expected"
  return 1
}

main "$@"
