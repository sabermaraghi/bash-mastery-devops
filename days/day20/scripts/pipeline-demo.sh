#!/usr/bin/env bash
# pipeline-demo.sh — compose the day's filters into one real tool.
#
# Shows the Unix philosophy in action: three tiny programs, each doing one
# thing, piped into a "top talkers" report — no monolith required. Also
# demonstrates why `set -o pipefail` matters for honest exit codes.
#
# Usage:
#   bash pipeline-demo.sh [LOGFILE] [FIELD]   # defaults: a sample log, field 1
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day20-demo.log}" COMPONENT="day20"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"

main() {
  local data="${1:-}" field="${2:-1}"
  if [[ -z "$data" ]]; then
    data="$(mktemp)"
    trap 'rm -f "${data:-}"' EXIT
    printf '%s\n' \
      "10.0.0.1 GET /" "10.0.0.2 GET /a" "10.0.0.1 GET /b" \
      "10.0.0.1 POST /c" "10.0.0.3 GET /d" "10.0.0.2 GET /e" \
      "10.0.0.1 GET /f" >"$data"
    log_info "using built-in sample log ($(wc -l <"$data") lines)"
  fi

  # Diagnostics go to stderr (log_*), DATA goes to stdout — so this whole tool
  # is itself a well-behaved filter you could pipe elsewhere.
  log_info "pipeline: field.sh $field | histogram.sh | bar.sh"
  set -o pipefail
  bash "$SCRIPT_DIR/field.sh" "$field" <"$data" |
    bash "$SCRIPT_DIR/histogram.sh" |
    bash "$SCRIPT_DIR/bar.sh"

  # A quick lesson on exit codes: without pipefail, a failing upstream stage is
  # hidden by a succeeding downstream one.
  set +o pipefail
  false | true
  log_info "without pipefail, 'false | true' exit code = $? (hides the failure)"
  set -o pipefail
  if ! { false | true; }; then
    log_info "with pipefail, the same pipeline correctly reports failure"
  fi
}

main "$@"
