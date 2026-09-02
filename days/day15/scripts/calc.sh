#!/usr/bin/env bash
# A tiny, well-tested library to demonstrate BATS testing patterns.
set -euo pipefail

add() { echo $(($1 + $2)); }
divide() {
  local a="$1" b="$2"
  if [[ "$b" -eq 0 ]]; then
    echo "error: division by zero" >&2
    return 1
  fi
  echo $((a / b))
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  "$@" # allow: calc.sh add 2 3
fi
