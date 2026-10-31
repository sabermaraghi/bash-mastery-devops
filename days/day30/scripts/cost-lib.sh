#!/usr/bin/env bash
# cost-lib.sh — parse workload specs + do the cost math (sourced).
#
# A workload is a key=value file describing what it asks for and what it uses:
#   name         = frontend
#   replicas     = 5
#   cpu_request  = 500     # millicores reserved per replica
#   mem_request  = 512     # MiB reserved per replica
#   cpu_usage    = 100     # millicores actually used (avg)
#   mem_usage    = 200     # MiB actually used (avg)
#
# Cost is what you PAY for (requests), not what you use — that gap is the waste.
set -euo pipefail

_trim() { printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

# spec_get <file> <key> — read one key=value field (ignores # comments).
spec_get() {
  local file="${1:?}" key="${2:?}" line val
  [[ -f "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*=(.*)$ ]]; then
      val="$(_trim "${BASH_REMATCH[1]}")"
      printf '%s' "$val"
      return 0
    fi
  done <"$file"
  return 1
}

# workload_cost <replicas> <cpu_millicores> <mem_mib> <cpu_price> <mem_price> <hours>
# Price model: $/core-hour for CPU, $/GiB-hour for memory.
workload_cost() {
  awk -v r="${1:?}" -v c="${2:?}" -v m="${3:?}" -v cp="${4:?}" -v mp="${5:?}" -v h="${6:?}" \
    'BEGIN { printf "%.2f", r * ((c / 1000) * cp + (m / 1024) * mp) * h }'
}
