#!/usr/bin/env bash
# log-tally.sh — fast, single-pass frequency counter for a log field.
#
# Counts how often each value of a whitespace-separated field appears and prints
# them "count value", highest first. One pass, an associative array, and zero
# forks per line — the pattern that replaces slow `sort | uniq -c | sort -rn`
# pipelines when you need in-shell control.
#
# Usage:
#   bash log-tally.sh <file> <field> [top_n]
#     <field>  1-based, whitespace-separated column
#     [top_n]  optional: print only the N most frequent values
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day19-tally.log}" COMPONENT="log-tally"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"

tally() {
  local file="${1:?file required}" field="${2:?field required}" top_n="${3:-0}"
  require_file "$file" || return 1
  FIELD_VAL="$field" require_int FIELD_VAL || return 1
  ((field >= 1)) || {
    log_error "field must be >= 1, got: $field"
    return 1
  }

  local -A counts=()
  local line idx=$((field - 1)) key
  local -a cols
  while IFS= read -r line || [[ -n "$line" ]]; do
    # shellcheck disable=SC2206  # deliberate word-split into fields
    cols=($line)
    key="${cols[idx]:-}"
    [[ -z "$key" ]] && continue
    counts["$key"]=$((${counts["$key"]:-0} + 1))
  done <"$file"

  # Emit "count<TAB>value", numerically sorted desc, then optional head.
  local out
  out="$(
    for key in "${!counts[@]}"; do
      printf '%s\t%s\n' "${counts[$key]}" "$key"
    done | sort -rn -k1,1
  )"
  if ((top_n > 0)); then
    printf '%s\n' "$out" | head -n "$top_n"
  else
    printf '%s\n' "$out"
  fi
}

tally "$@"
