#!/usr/bin/env bash
# bar.sh — a filter: turn "count value" lines into an ASCII bar chart.
#
# One job: read "count[whitespace]value" on stdin, scale bars to the largest
# count, and render them. Completes the pipeline:
#   field.sh 1 < access.log | histogram.sh | bar.sh
#
# Bar width is configurable with BAR_WIDTH (default 40).
set -euo pipefail

width="${BAR_WIDTH:-40}"
mapfile -t rows
((${#rows[@]} > 0)) || exit 0

max=0
for r in "${rows[@]}"; do
  read -r cnt _ <<<"$r"
  [[ "$cnt" =~ ^[0-9]+$ ]] || continue
  ((cnt > max)) && max="$cnt"
done
((max > 0)) || exit 0

for r in "${rows[@]}"; do
  read -r cnt val <<<"$r"
  [[ "$cnt" =~ ^[0-9]+$ ]] || continue
  len=$((cnt * width / max))
  ((len < 1)) && len=1
  bar="$(printf '%*s' "$len" '')"
  bar="${bar// /#}"
  printf '%-16s | %-*s %s\n' "$val" "$width" "$bar" "$cnt"
done
