#!/usr/bin/env bash
# rightsize.sh — find waste and risk, recommend better resource requests.
#
# Compares each workload's usage against its requests:
#   utilization < --low   -> WASTE  (over-provisioned, you're paying for air)
#   utilization > --high  -> RISK   (under-provisioned, one spike from OOM)
#   otherwise             -> OK
# Recommends requests that leave --target% headroom, and prices the monthly
# saving. Exits non-zero if anything needs attention — a FinOps CI gate.
#
# Usage:
#   bash rightsize.sh --dir DIR [--low 30] [--high 90] [--target 60] \
#        [--cpu-price P] [--mem-price P] [--hours H]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day30-cost.log}" COMPONENT="rightsize"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/cost-lib.sh"

usage() {
  echo "usage: $0 --dir DIR [--low 30] [--high 90] [--target 60] [--cpu-price P] [--mem-price P] [--hours H]" >&2
  exit 2
}

main() {
  local dir="" low=30 high=90 target=60 cpu_price="0.031" mem_price="0.004" hours="730"
  while (($#)); do
    case "$1" in
      --dir)
        dir="${2:?}"
        shift
        ;;
      --low)
        low="${2:?}"
        shift
        ;;
      --high)
        high="${2:?}"
        shift
        ;;
      --target)
        target="${2:?}"
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

  printf '%-14s %-6s %9s %9s %10s %10s %10s\n' \
    "WORKLOAD" "STATUS" "CPU%" "MEM%" "REC_CPU" "REC_MEM" "SAVE/MO$"
  printf '%-14s %-6s %9s %9s %10s %10s %10s\n' \
    "--------------" "------" "--------" "--------" "---------" "---------" "---------"

  local f name replicas cpu_req mem_req cpu_use mem_use line
  local savings="" flagged=0 found=0
  shopt -s nullglob
  for f in "$dir"/*.workload; do
    found=1
    name="$(spec_get "$f" name || basename "$f" .workload)"
    replicas="$(spec_get "$f" replicas || echo 1)"
    cpu_req="$(spec_get "$f" cpu_request || echo 0)"
    mem_req="$(spec_get "$f" mem_request || echo 0)"
    cpu_use="$(spec_get "$f" cpu_usage || echo 0)"
    mem_use="$(spec_get "$f" mem_usage || echo 0)"

    line="$(awk -v r="$replicas" -v cr="$cpu_req" -v mr="$mem_req" -v cu="$cpu_use" -v mu="$mem_use" \
      -v low="$low" -v high="$high" -v tgt="$target" -v cp="$cpu_price" -v mp="$mem_price" -v h="$hours" 'BEGIN {
        cutil = (cr > 0) ? cu / cr * 100 : 0
        mutil = (mr > 0) ? mu / mr * 100 : 0
        status = "OK"
        if (cutil >= high || mutil >= high) status = "RISK"
        else if (cutil < low || mutil < low) status = "WASTE"
        reccr = cr; recmr = mr
        if (status != "OK") {
          reccr = ceil(cu / (tgt / 100)); recmr = ceil(mu / (tgt / 100))
          if (reccr < 1) reccr = 1
          if (recmr < 1) recmr = 1
        }
        cur = r * ((cr / 1000) * cp + (mr / 1024) * mp) * h
        rec = r * ((reccr / 1000) * cp + (recmr / 1024) * mp) * h
        printf "%s\t%.0f\t%.0f\t%d\t%d\t%.2f", status, cutil, mutil, reccr, recmr, cur - rec
      }
      function ceil(x) { return (x == int(x)) ? x : int(x) + 1 }')"

    local status cutil mutil reccr recmr save
    IFS=$'\t' read -r status cutil mutil reccr recmr save <<<"$line"
    [[ "$status" == "OK" ]] || flagged=1
    savings+="$save"$'\n'
    printf '%-14s %-6s %8s%% %8s%% %10s %10s %10s\n' \
      "$name" "$status" "$cutil" "$mutil" "$reccr" "$recmr" "$save"
  done
  shopt -u nullglob

  ((found)) || {
    log_error "no *.workload files in $dir"
    return 1
  }

  local net
  net="$(printf '%s' "$savings" | awk '{ s += $1 } END { printf "%.2f", s }')"
  printf '%-14s %-6s %9s %9s %10s %10s %10s\n' \
    "--------------" "------" "--------" "--------" "---------" "---------" "---------"
  printf 'Potential monthly savings: $%s\n' "$net"
  if ((flagged)); then
    echo "RESULT: workloads need right-sizing"
    return 1
  fi
  echo "RESULT: all workloads right-sized"
}

main "$@"
