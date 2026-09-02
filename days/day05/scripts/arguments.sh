#!/usr/bin/env bash
# Positional arguments and the special parameters around them.
set -euo pipefail

echo "Script name : $0"
echo "Arg count   : $#"
echo "First arg    : ${1:-<none>}"
echo "All args (@): $*"

if [[ $# -eq 0 ]]; then
  echo "No arguments passed. Try: $0 alpha beta"
  exit 0
fi

i=1
for arg in "$@"; do
  echo "  arg[$i] = $arg"
  i=$((i + 1))
done
