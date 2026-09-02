#!/usr/bin/env bash
# drift-detect.sh — report divergence between DESIRED and LIVE, read-only.
#
# The GitOps guardrail: run it on a schedule (or in CI) to catch out-of-band
# changes. Exits 0 when LIVE matches DESIRED, non-zero when drift is found — so
# it plugs straight into an alert or a gate. Never modifies anything.
#
# Usage: bash drift-detect.sh DESIRED_DIR LIVE_DIR
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day24-drift.log}" COMPONENT="drift-detect"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/gitops-lib.sh"

main() {
  local desired="${1:-}" live="${2:-}"
  [[ -n "$desired" && -n "$live" ]] || {
    echo "usage: $0 DESIRED_DIR LIVE_DIR" >&2
    exit 2
  }
  require_dir "$desired" || return 1
  require_dir "$live" || return 1

  local changes count
  changes="$(diff_state "$desired" "$live")" || true

  if [[ -z "$changes" ]]; then
    echo "no drift: LIVE matches DESIRED"
    return 0
  fi

  printf '%s\n' "$changes"
  count="$(printf '%s\n' "$changes" | grep -c .)"
  echo "----------------------------"
  echo "drift detected: $count file(s) diverged"
  log_error "drift detected ($count files)"
  return 1
}

main "$@"
