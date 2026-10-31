#!/usr/bin/env bash
# Run independent work concurrently, bound the fan-out, and collect results.
set -euo pipefail

process() {
  local item="$1"
  sleep 0.1
  echo "processed:$item"
}

items=(alpha bravo charlie delta echo foxtrot)
MAX_PARALLEL=3
out="$(mktemp)"
trap 'rm -f "$out"' EXIT

running=0
for item in "${items[@]}"; do
  process "$item" >>"$out" &
  ((++running >= MAX_PARALLEL)) && {
    wait -n 2>/dev/null || wait
    running=$((running - 1))
  }
done
wait

echo "Processed $(wc -l <"$out") items concurrently (cap: $MAX_PARALLEL)"
sort "$out"
