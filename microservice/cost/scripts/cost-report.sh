#!/usr/bin/env bash
set -euo pipefail
DAYS="$1"
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "$DAYS days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json | jq '{total: (.ResultsByTime[].Total.UnblendedCost.Amount | tonumber), services: [.ResultsByTime[].Groups[] | {service: .Keys[0], cost: (.Metrics.UnblendedCost.Amount | tonumber)}]}'
