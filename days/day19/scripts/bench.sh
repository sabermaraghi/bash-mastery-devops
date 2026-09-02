#!/usr/bin/env bash
# bench.sh — a tiny micro-benchmark harness.
#
# Use it two ways:
#   CLI:      bash bench.sh <iterations> <label> <command> [args...]
#   Sourced:  source bench.sh; bench <iterations> <label> my_function [args...]
#
# Timing prefers bash 5's EPOCHREALTIME (no fork) and falls back to `date`.
set -euo pipefail

bench() {
  local iters="${1:?iterations required}" label="${2:?label required}"
  shift 2
  [[ "$iters" =~ ^[0-9]+$ ]] || {
    echo "iterations must be an integer" >&2
    return 2
  }
  local start end i=0
  start="${EPOCHREALTIME:-$(date +%s.%N)}"
  while ((i < iters)); do
    "$@" >/dev/null 2>&1 || true
    i=$((i + 1))
  done
  end="${EPOCHREALTIME:-$(date +%s.%N)}"
  # Float math without bc: let awk do the subtraction and per-run average.
  awk -v s="$start" -v e="$end" -v n="$iters" -v l="$label" 'BEGIN {
    total = e - s
    avg_ms = (n > 0 ? (total / n) * 1000 : 0)
    printf "%-24s %6d runs  total %8.3fs  avg %8.4f ms\n", l, n, total, avg_ms
  }'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if (($# < 3)); then
    echo "usage: $0 <iterations> <label> <command> [args...]" >&2
    exit 2
  fi
  bench "$@"
fi
