#!/usr/bin/env bash
# log-analyzer.sh — CAPSTONE: a production-grade access-log analyzer.
#
# Pulls together the whole course:
#   - strict mode + traps + shared logging  (Day 11 / lib/logging.sh)
#   - input validation                       (Day 17 / lib/validator.sh)
#   - single-pass, fork-free parsing         (Day 19)
#   - clean stdout data / stderr diagnostics (Day 20)
#
# Parses combined/common web log format:
#   IP - - [timestamp] "METHOD PATH PROTO" STATUS SIZE
# and reports a summary, top talkers, top paths, and status/method breakdowns.
#
# Usage:
#   bash log-analyzer.sh [-n TOP] [-o OUTFILE] LOGFILE
#     -n TOP     how many rows in each "top" table (default 10)
#     -o OUTFILE write the report here instead of stdout
#     -h         help
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day21-analyzer.log}" COMPONENT="log-analyzer"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"

usage() {
  echo "usage: $0 [-n TOP] [-o OUTFILE] LOGFILE" >&2
  exit 2
}

# Render an assoc array as a "count<TAB>key" table, sorted desc, limited to N.
# Uses awk (not head) to cap rows so no upstream SIGPIPE under pipefail.
print_table() {
  local -n _map="$1"
  local top="$2" k
  {
    for k in "${!_map[@]}"; do
      printf '%s\t%s\n' "${_map[$k]}" "$k"
    done
  } | sort -rn -k1,1 | awk -v n="$top" 'NR<=n'
}

analyze() {
  local file="$1" top="$2"
  require_file "$file" || return 1

  local -A by_ip=() by_path=() by_status=() by_method=()
  local total=0 malformed=0 bytes=0 errors=0
  local line ip method path status size
  local -a f

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    read -ra f <<<"$line"
    # combined format needs at least 10 whitespace fields
    if ((${#f[@]} < 10)); then
      malformed=$((malformed + 1))
      continue
    fi
    ip="${f[0]}"
    method="${f[5]#\"}"
    path="${f[6]}"
    status="${f[8]}"
    size="${f[9]}"
    if ! [[ "$status" =~ ^[0-9]{3}$ ]]; then
      malformed=$((malformed + 1))
      continue
    fi

    total=$((total + 1))
    by_ip["$ip"]=$((${by_ip["$ip"]:-0} + 1))
    by_path["$path"]=$((${by_path["$path"]:-0} + 1))
    by_status["$status"]=$((${by_status["$status"]:-0} + 1))
    by_method["$method"]=$((${by_method["$method"]:-0} + 1))
    [[ "$size" =~ ^[0-9]+$ ]] && bytes=$((bytes + size))
    ((status >= 400)) && errors=$((errors + 1))
  done <"$file"

  local rate="0.0"
  ((total > 0)) && rate="$(awk -v e="$errors" -v t="$total" 'BEGIN{printf "%.1f", (e/t)*100}')"

  # ---- report (stdout only; diagnostics went to stderr via log_*) ----
  echo "===== Log Analyzer Pro ====="
  echo "file:            $file"
  echo "total requests:  $total"
  echo "malformed lines: $malformed"
  echo "unique IPs:      ${#by_ip[@]}"
  echo "total bytes:     $bytes"
  echo "errors (>=400):  $errors"
  echo "error rate:      ${rate}%"
  echo
  echo "----- Top $top IPs -----"
  print_table by_ip "$top"
  echo
  echo "----- Top $top paths -----"
  print_table by_path "$top"
  echo
  echo "----- Status codes -----"
  print_table by_status "$top"
  echo
  echo "----- Methods -----"
  print_table by_method "$top"
}

main() {
  local top=10 outfile=""
  local opt
  while getopts ":n:o:h" opt; do
    case "$opt" in
      n) top="$OPTARG" ;;
      o) outfile="$OPTARG" ;;
      h) usage ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))

  local file="${1:-}"
  [[ -n "$file" ]] || usage
  TOP_VAL="$top" require_int TOP_VAL || {
    log_error "-n must be a non-negative integer"
    return 1
  }
  ((top >= 1)) || {
    log_error "-n must be >= 1"
    return 1
  }

  log_info "analyzing $file (top $top)"
  if [[ -n "$outfile" ]]; then
    analyze "$file" "$top" >"$outfile"
    log_info "report written to $outfile"
  else
    analyze "$file" "$top"
  fi
}

main "$@"
