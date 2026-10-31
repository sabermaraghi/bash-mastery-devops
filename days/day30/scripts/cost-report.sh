#!/usr/bin/env bash
# cost-report.sh — what the cluster costs, per workload and in total.
#
# Reads every *.workload in a directory and prices its resource *requests*
# (what you reserve = what you pay). Defaults model a typical cloud rate:
#   CPU  $0.031 / core-hour   Memory  $0.004 / GiB-hour   730 hours = 1 month
#
# Usage:
#   bash cost-report.sh --dir DIR [--cpu-price P] [--mem-price P] [--hours H]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day30-cost.log}" COMPONENT="cost-report"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/cost-lib.sh"

usage() {
  echo "usage: $0 --dir DIR [--cpu-price P] [--mem-price P] [--hours H]" >&2
  exit 2
}

main() {
  local dir="" cpu_price="0.031" mem_price="0.004" hours="730"
  while (($#)); do
    case "$1" in
      --dir)
        dir="${2:?}"
        shift
        ;;
      --cpu-price)
        cpu_price="${2:?}"
        shift
        ;;
      --mem-price)
        mem_price="${2:?}"
        shift
        ;;
      --hours)
        hours="${2:?}"
        shift
        ;;
      -h | --help) usage ;;
      -*)
        echo "unknown flag: $1" >&2
        usage
        ;;
      *) usage ;;
    esac
    shift
  done
  [[ -n "$dir" ]] || usage
  require_dir "$dir" || return 1

  printf '%-16s %8s %8s %8s %12s\n' "WORKLOAD" "REPLICAS" "CPU(m)" "MEM(Mi)" "COST/MO($)"
  printf '%-16s %8s %8s %8s %12s\n' "----------------" "--------" "------" "-------" "------------"

  local f name replicas cpu_req mem_req cost costs="" total found=0
  shopt -s nullglob
  for f in "$dir"/*.workload; do
    found=1
    name="$(spec_get "$f" name || basename "$f" .workload)"
    replicas="$(spec_get "$f" replicas || echo 1)"
    cpu_req="$(spec_get "$f" cpu_request || echo 0)"
    mem_req="$(spec_get "$f" mem_request || echo 0)"
    cost="$(workload_cost "$replicas" "$cpu_req" "$mem_req" "$cpu_price" "$mem_price" "$hours")"
    costs+="$cost"$'\n'
    printf '%-16s %8s %8s %8s %12s\n' "$name" "$replicas" "$cpu_req" "$mem_req" "$cost"
  done
  shopt -u nullglob

  ((found)) || {
    log_error "no *.workload files in $dir"
    return 1
  }

  total="$(printf '%s' "$costs" | awk '{ s += $1 } END { printf "%.2f", s }')"
  printf '%-16s %8s %8s %8s %12s\n' "----------------" "--------" "------" "-------" "------------"
  printf '%-16s %8s %8s %8s %12s\n' "TOTAL" "" "" "" "$total"
}

main "$@"
