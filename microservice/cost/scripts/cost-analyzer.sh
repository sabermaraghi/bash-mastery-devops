#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PROVIDER="$1"
DAYS="$2"
GRANULARITY="$3"
FORECAST_DAYS="${4:-0}"
BUDGET="${5:-0}"

readonly AUDIT_LOG="/var/log/cost-audit.log"
readonly LOCK="/var/run/cost-analyzer.lock"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [COST] $*" | tee -a "$AUDIT_LOG"
}

acquire_lock() {
  exec 200>"$LOCK"
  flock -n 200 || (log "Another analysis running"; exit 1)
}

analyze_aws() {
  local days="$1"
  local granularity="$2"
  local forecast="$3"
  local budget="$4"

  total=$(aws ce get-cost-and-usage \
    --time-period Start=$(date -d "$days days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
    --granularity "$granularity" \
    --metrics "UnblendedCost" \
    --query "ResultsByTime[*].Total.UnblendedCost.Amount" \
    --output text | awk '{sum+=$1} END {print sum}')

  top_services=$(aws ce get-cost-and-usage \
    --time-period Start=$(date -d "$days days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
    --granularity MONTHLY \
    --group-by Type=DIMENSION,Key=SERVICE \
    --metrics "UnblendedCost" \
    --query "ResultsByTime[*].Groups[].[Keys[0],Amount]" \
    --output json | jq -c 'sort_by(.[1] | tonumber) | reverse | .[:5]')

  alert=""
  if (( $(echo "$total > $budget" | bc -l 2>/dev/null || echo 0) )); then
    alert="BUDGET EXCEEDED: €$total > €$budget"
  fi

  forecast=""
  if [[ "$forecast" -gt 0 ]]; then
    daily_avg=$(echo "$total / $days" | bc -l)
    projected=$(echo "$daily_avg * ($days + $forecast)" | bc -l)
    forecast=$(jq -n \
      --argjson days "$forecast" \
      --argjson projected "$(printf "%.2f" "$projected")" \
      '{days: $days, projected_cost_eur: $projected}')
  fi

  echo '{
    "total_cost": '"${total:-0.0}"',
    "currency": "EUR",
    "period": "Last '"$days"' days",
    "top_services": '"${top_services:-[]}"',
    "forecast": '"${forecast:-null}"',
    "alert": '"$(jq -n --arg a "$alert" '$a')"'
  }'
}

acquire_lock
trap 'flock -u 200; rm -f "$LOCK"' EXIT

case "$PROVIDER" in
  "aws"|"all")
    analyze_aws "$DAYS" "$GRANULARITY" "$FORECAST_DAYS" "$BUDGET"
    ;;
  *)
    log "Unsupported provider: $PROVIDER"
    exit 1
    ;;
esac
