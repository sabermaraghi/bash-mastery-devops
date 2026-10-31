#!/usr/bin/env bash
# zero-trust-pipeline.sh — a fail-closed pipeline that verifies at every stage.
#
# Zero-trust means: trust nothing by default, verify at each gate, and STOP the
# moment a gate fails (fail-closed) so bad code/artifacts never flow downstream.
#
# Stages, in order:
#   1. syntax    — every *.sh under <dir> must pass `bash -n`
#   2. secrets   — Day 17's secret-scanner must find no hardcoded credentials
#   3. integrity — if <dir>/SHA256SUMS exists, it must verify
#
# Usage:
#   bash zero-trust-pipeline.sh <dir>     # run the gates, fail-closed
#   bash zero-trust-pipeline.sh --list    # print the ordered stages
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day18-pipeline.log}" COMPONENT="zero-trust"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"

SCANNER="$REPO_ROOT/days/day17/scripts/secret-scanner.sh"
VERIFIER="$SCRIPT_DIR/verify-artifact.sh"
STAGES=(syntax secrets integrity)

gate_syntax() {
  local dir="$1" rc=0 tmp
  tmp="$(mktemp)"
  trap 'rm -f "${tmp:-}"' RETURN
  find "$dir" -type f -name '*.sh' >"$tmp" 2>/dev/null || true
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    bash -n "$f" || {
      log_error "syntax error in $f"
      rc=1
    }
  done <"$tmp"
  return "$rc"
}

gate_secrets() { bash "$SCANNER" "$1" >/dev/null 2>&1; }

gate_integrity() {
  local dir="$1"
  [[ -f "$dir/SHA256SUMS" ]] || {
    log_info "integrity: no manifest, skipping (nothing to verify)"
    return 0
  }
  bash "$VERIFIER" verify "$dir" >/dev/null 2>&1
}

run_pipeline() {
  local dir="${1:?dir required}"
  [[ -d "$dir" ]] || {
    log_error "not a directory: $dir"
    return 2
  }
  local stage
  for stage in "${STAGES[@]}"; do
    log_info "stage: $stage — running"
    if "gate_$stage" "$dir"; then
      log_info "stage: $stage — PASS"
    else
      # fail-closed: abort immediately, do not run later stages
      log_error "stage: $stage — FAIL (pipeline halted, fail-closed)"
      return 1
    fi
  done
  log_info "pipeline PASSED: all gates green for $dir"
  return 0
}

main() {
  case "${1:-}" in
    --list)
      printf '%s\n' "${STAGES[@]}"
      ;;
    "" | -h | --help)
      echo "usage: $0 <dir> | --list" >&2
      return 2
      ;;
    *)
      run_pipeline "$1"
      ;;
  esac
}

main "$@"
