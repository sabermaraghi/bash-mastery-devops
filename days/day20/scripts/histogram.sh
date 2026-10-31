#!/usr/bin/env bash
# histogram.sh — a filter: count how often each stdin line occurs.
#
# One job: read values on stdin, emit "count<TAB>value" sorted most-frequent
# first. Pairs perfectly with field.sh:
#   field.sh 1 < access.log | histogram.sh
set -euo pipefail

declare -A counts=()
while IFS= read -r v || [[ -n "$v" ]]; do
  [[ -z "$v" ]] && continue
  counts["$v"]=$((${counts["$v"]:-0} + 1))
done

for k in "${!counts[@]}"; do
  printf '%s\t%s\n' "${counts[$k]}" "$k"
done | sort -rn -k1,1
