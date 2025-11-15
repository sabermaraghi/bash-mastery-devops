# Day 9: Environment Variables & Sourcing

> **Goal**: Control script behavior via environment, share configs, and build reusable libraries.

## 1. Environment Variables

export DB_HOST="prod-db.example.com"
export DEBUG=true

./script.sh         # Inherits env

## 2. Sourcing Files

# lib/config.sh
DB_USER="admin"
DB_PASS="secret123"

# main.sh
source "./lib/config.sh"
echo "Connecting to $DB_USER@$DB_HOST"

## 3. Best Practices
- Use readonly for constants
- Validate required vars
- Use .env + source pattern

## 4. Production Example: Config Loader

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


