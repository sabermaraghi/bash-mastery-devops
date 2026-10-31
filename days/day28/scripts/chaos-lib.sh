#!/usr/bin/env bash
# chaos-lib.sh — safety + selection helpers for chaos experiments (sourced).
#
# Works on the Day 26 "cluster": pods are files at <state>/pods/<name>-<index>.
# The golden rules baked in here:
#   1. verify STEADY STATE before injecting (never kick a system that's down)
#   2. cap the BLAST RADIUS (never take out more than you meant to)
#   3. selection is DETERMINISTIC given a --seed (reproducible experiments)
set -euo pipefail

# list_pods <pods-dir> <name> — basenames of this app's pods, sorted.
list_pods() {
  local dir="${1:?}" name="${2:?}" pod base idx
  [[ -d "$dir" ]] || return 0
  shopt -s nullglob
  for pod in "$dir/${name}-"*; do
    base="${pod##*/}"
    idx="${base##*-}"
    [[ "$idx" =~ ^[0-9]+$ ]] && printf '%s\n' "$base"
  done
  shopt -u nullglob
}

count_pods() { list_pods "${1:?}" "${2:?}" | grep -c . || true; }

# blast_cap <total> <max_percent> — max pods allowed to be affected (floor).
blast_cap() {
  local total="${1:?}" pct="${2:?}"
  printf '%s' "$((total * pct / 100))"
}

# pick_victims <pods-dir> <name> <count> <seed> — deterministic random selection.
# Ranks pods by a seeded hash, then takes the first <count>. Same seed => same
# victims, so an experiment is reproducible. awk (not head) caps rows to avoid
# SIGPIPE under pipefail.
pick_victims() {
  local dir="${1:?}" name="${2:?}" count="${3:?}" seed="${4:?}" p h
  list_pods "$dir" "$name" | while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    h="$(printf '%s' "${seed}:${p}" | sha256sum | cut -c1-16)"
    printf '%s\t%s\n' "$h" "$p"
  done | sort | awk -v n="$count" 'NR<=n{print $2}'
}

# is_int <value> — non-negative integer? (value check, unlike require_int)
is_int() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
