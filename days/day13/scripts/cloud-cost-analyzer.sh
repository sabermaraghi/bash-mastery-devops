#!/usr/bin/env bash
set -euo pipefail

DAYS=7
REPORT="aws-cost-$(date +%Y%m%d).json"

command -v aws &>/dev/null || {
  echo "ERROR: aws CLI is not installed"
  exit 1
}
command -v jq &>/dev/null || {
  echo "ERROR: jq is not installed"
  exit 1
}

analyze_service() {
  local service="$1"
  local start end
  start=$(date -d "$DAYS days ago" +%Y-%m-%d)
  end=$(date +%Y-%m-%d)
  aws ce get-cost-and-usage \
    --time-period Start="$start",End="$end" \
    --granularity DAILY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter "{\"Dimensions\":{\"Key\":\"SERVICE\",\"Values\":[\"$service\"]}}" \
    --output json >"/tmp/cost-$service.json"
}
export -f analyze_service
export DAYS

services=("AmazonEC2" "AmazonS3" "AWSLambda" "AmazonRDS")
for s in "${services[@]}"; do
  analyze_service "$s" &
done
wait

# Properly sum cost per service across all days, instead of jq -s 'add'
# (which was shallow-merging whole response objects and losing data)
jq -s '
  [.[] | .ResultsByTime[]?.Groups[]? | {
    service: .Keys[0],
    cost: (.Metrics.UnblendedCost.Amount | tonumber)
  }]
  | group_by(.service)
  | map({service: .[0].service, total_cost: (map(.cost) | add)})
' /tmp/cost-*.json >"$REPORT"

echo "AWS expense report: $REPORT"
