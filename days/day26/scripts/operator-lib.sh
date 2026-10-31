#!/usr/bin/env bash
# operator-lib.sh — shared helpers for a tiny Kubernetes-style operator.
#
# A CustomResource (CR) is a simple key=value manifest, e.g. a WidgetSet:
#   kind = WidgetSet
#   name = frontend
#   replicas = 3
#   image = nginx:1.25
#
# "Pods" are just files under <state>/pods/<name>-<index> whose content is the
# image — enough to demonstrate the reconcile pattern without a real cluster.
set -euo pipefail

_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# cr_get <cr-file> <key> — print the value for key, or return 1 if absent.
cr_get() {
  local file="${1:?cr file required}" key="${2:?key required}" line k
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(_trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || continue
    k="$(_trim "${line%%=*}")"
    if [[ "$k" == "$key" ]]; then
      _trim "${line#*=}"
      return 0
    fi
  done <"$file"
  return 1
}

# is_uint <value> — non-negative integer?
is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

# count_pods <pods-dir> <name> — how many pods currently exist for this CR.
count_pods() {
  local dir="${1:?}" name="${2:?}" n=0 pod base idx
  shopt -s nullglob
  for pod in "$dir/${name}-"*; do
    base="${pod##*/}"
    idx="${base##*-}"
    [[ "$idx" =~ ^[0-9]+$ ]] && n=$((n + 1))
  done
  shopt -u nullglob
  printf '%s' "$n"
}
