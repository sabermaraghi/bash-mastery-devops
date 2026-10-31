#!/usr/bin/env bash
# field.sh — a filter: print the Nth whitespace-separated field of each line.
#
# Unix philosophy: do ONE thing, read stdin, write stdout, diagnostics to
# stderr, meaningful exit code. That's all this does — so it composes freely:
#   cat access.log | field.sh 1 | sort | uniq -c
set -euo pipefail

n="${1:?usage: field.sh N   (1-based field index)}"
[[ "$n" =~ ^[0-9]+$ ]] && ((n >= 1)) || {
  echo "field.sh: N must be an integer >= 1 (got: $n)" >&2
  exit 2
}
idx=$((n - 1))

while IFS= read -r line || [[ -n "$line" ]]; do
  read -ra cols <<<"$line"
  key="${cols[idx]:-}"
  [[ -n "$key" ]] && printf '%s\n' "$key"
done
