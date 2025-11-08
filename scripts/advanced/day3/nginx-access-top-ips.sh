#!/bin/bash
set -euo pipefail

LOG="/var/log/nginx/access.log"

if [[ ! -f "$LOG" ]]; then
  echo "Nginx log not found: $LOG"
  exit 1
fi

echo "Top 10 IPs in Nginx access log:"
echo "================================"

awk '{print $1}' "$LOG" | sort | uniq -c | sort -nr | head -10 | awk '{printf "%4d × %s\n", $1, $2}'
