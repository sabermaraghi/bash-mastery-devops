#!/usr/bin/env bash
# pipeline-lib.sh — a tiny, reusable CI/CD engine (sourced library).
#
# Progress lines go to stderr; the machine-readable results table + summary go
# to stdout — so a pipeline run is itself a well-behaved filter (Day 20).
#
#   source pipeline-lib.sh
#   run_stage lint  bash -n script.sh
#   run_stage test  ./run-tests.sh
#   pipeline_summary            # exits non-zero if any stage failed
set -euo pipefail

_PIPELINE_PASS=0
_PIPELINE_FAIL=0
declare -a _PIPELINE_RESULTS=()

# run_stage <name> <command...> — execute one stage, record + report result.
# Returns the stage's exit code (never aborts the caller on its own).
run_stage() {
  local name="${1:?stage name required}"
  shift
  local start end dur rc=0
  printf '▶ %s\n' "$name" >&2
  start="${EPOCHREALTIME:-$(date +%s)}"
  "$@" || rc=$?
  end="${EPOCHREALTIME:-$(date +%s)}"
  dur="$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.2f", e-s}')"
  if ((rc == 0)); then
    _PIPELINE_PASS=$((_PIPELINE_PASS + 1))
    _PIPELINE_RESULTS+=("PASS  ${name}  ${dur}s")
    printf '  ✓ %s (%ss)\n' "$name" "$dur" >&2
  else
    _PIPELINE_FAIL=$((_PIPELINE_FAIL + 1))
    _PIPELINE_RESULTS+=("FAIL  ${name}  ${dur}s  rc=${rc}")
    printf '  ✗ %s (%ss) rc=%s\n' "$name" "$dur" "$rc" >&2
  fi
  return "$rc"
}

# pipeline_summary — print the results table + totals; exit non-zero on any fail.
pipeline_summary() {
  echo "===== pipeline summary ====="
  if ((${#_PIPELINE_RESULTS[@]} > 0)); then
    printf '%s\n' "${_PIPELINE_RESULTS[@]}"
  fi
  echo "----------------------------"
  printf 'summary: %s passed, %s failed\n' "$_PIPELINE_PASS" "$_PIPELINE_FAIL"
  ((_PIPELINE_FAIL == 0))
}
