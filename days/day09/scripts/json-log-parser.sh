#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/app/json.log"
REPORT="json-report-$(date +%Y%m%d).txt"

command -v jq &>/dev/null || {
  echo "ERROR: jq is not installed"
  exit 1
}

mapfile -t lines < <(tail -100000 "$LOG_FILE")

echo "Analysing 100,000 JSON log lines..." >"$REPORT"

# Single jq pass over all lines, instead of three separate passes
printf '%s\n' "${lines[@]}" | jq -s '
  {
    errors: ([.[] | select(.level=="ERROR")] | length),
    warnings: ([.[] | select(.level=="WARN")] | length),
    top_5_ips: ([.[].ip] | group_by(.) | map({ip: .[0], count: length}) | sort_by(-.count) | .[0:5])
  }' >>"$REPORT"

echo "Report saved: $REPORT"
