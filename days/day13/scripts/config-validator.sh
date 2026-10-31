#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="/etc/app-configs"
THREADS=50

command -v yq &>/dev/null || {
  echo "ERROR: yq is not installed"
  exit 1
}

validate_file() {
  local file="$1"
  if yq eval '.' "$file" >/dev/null 2>&1; then
    echo "OK: $file"
  else
    echo "INVALID: $file" >&2
  fi
}

export -f validate_file
find "$CONFIG_DIR" -name "*.yaml" -o -name "*.yml" | xargs -P "$THREADS" -I {} bash -c 'validate_file "{}"'
