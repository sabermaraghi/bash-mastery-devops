#!/usr/bin/env bash
# health-lib.sh — liveness probes + restart bookkeeping for self-healing.
#
# Reuses the Day 26 "cluster": pods are files at <state>/pods/<name>-<index>
# whose content is the running image. A pod is considered ALIVE unless it's:
#   - missing        (the file doesn't exist)
#   - empty          (crashed before writing anything)
#   - marked CRASHED  (an explicit crash marker)
#   - a :bad image    (an image that crashes on start — drives CrashLoopBackOff)
set -euo pipefail

is_int() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

# probe_pod <pod-file> — liveness probe. 0 = alive, 1 = needs restart.
probe_pod() {
  local pod="${1:?}" content
  [[ -f "$pod" ]] || return 1
  content="$(cat "$pod")"
  [[ -n "$content" ]] || return 1
  [[ "$content" == *CRASHED* ]] && return 1
  [[ "$content" == *:bad* ]] && return 1
  return 0
}

# healthy_count <pods-dir> <name> <replicas> — how many of 0..replicas-1 are alive.
healthy_count() {
  local dir="${1:?}" name="${2:?}" replicas="${3:?}" i n=0
  for ((i = 0; i < replicas; i++)); do
    probe_pod "$dir/${name}-${i}" && n=$((n + 1))
  done
  printf '%s' "$n"
}

# restart_count <restarts-dir> <pod-name> — read persisted restart count (0 default).
restart_count() {
  local dir="${1:?}" pod="${2:?}" v
  v="$(cat "$dir/$pod" 2>/dev/null || echo 0)"
  is_int "$v" || v=0
  printf '%s' "$v"
}
