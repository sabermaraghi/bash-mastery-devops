#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-./config.env}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: $CONFIG_FILE not found" >&2
  exit 1
fi

source "$CONFIG_FILE"

required_vars=(DB_HOST DB_USER API_KEY)
for var in "${required_vars[@]}"; do
  [[ -z "${!var:-}" ]] && echo "Error: $var is required" && exit 1
done

echo "Config loaded: $DB_USER@$DB_HOST"
