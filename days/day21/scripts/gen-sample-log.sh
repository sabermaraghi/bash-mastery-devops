#!/usr/bin/env bash
# gen-sample-log.sh — emit N lines of deterministic combined-format access log.
#
# Deterministic (no randomness) so tests and demos get predictable counts.
# Format: IP - - [ts] "METHOD PATH HTTP/1.0" STATUS SIZE
#
# Usage: bash gen-sample-log.sh [N]     # default 100 lines
set -euo pipefail

n="${1:-100}"
[[ "$n" =~ ^[0-9]+$ ]] || {
  echo "usage: gen-sample-log.sh [N]" >&2
  exit 2
}

ips=(10.0.0.1 10.0.0.2 10.0.0.3)
paths=(/ /login /api/data /static/app.js /missing)
methods=(GET GET GET POST)
statuses=(200 200 200 404 500)

i=0
while ((i < n)); do
  ip="${ips[i % ${#ips[@]}]}"
  path="${paths[i % ${#paths[@]}]}"
  method="${methods[i % ${#methods[@]}]}"
  status="${statuses[i % ${#statuses[@]}]}"
  size=$(((i * 37 % 900) + 100))
  printf '%s - - [10/Oct/2000:13:55:%02d -0700] "%s %s HTTP/1.0" %s %s\n' \
    "$ip" "$((i % 60))" "$method" "$path" "$status" "$size"
  i=$((i + 1))
done
