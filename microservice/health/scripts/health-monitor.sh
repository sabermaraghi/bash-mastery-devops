#!/usr/bin/env bash
set -euo pipefail

API_URL="http://localhost:8000"
LOG="/var/log/health-monitor.log"
LOCK="/var/run/health-monitor.lock"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [HEALTH] $*" | tee -a "$LOG"
}

acquire_lock() {
  exec 200>"$LOCK"
  flock -n 200 || (log "Another monitor running"; exit 1)
}

check_probe() {
  local probe="$1"
  if curl -sf "$API_URL/health/$probe" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

self_heal() {
  log "SELF-HEALING: Restarting container"
  curl -X POST "$API_URL/simulate/recover" || true
  # In real pod: kubectl delete pod $HOSTNAME -n $NAMESPACE
  log "Recovery triggered"
}

acquire_lock
trap 'flock -u 200; rm -f "$LOCK"' EXIT

while true; do
  if ! check_probe "liveness"; then
    log "LIVENESS FAILED"
    self_heal
    break
  fi
  if ! check_probe "readiness"; then
    log "READINESS FAILED - traffic blocked"
  fi
  sleep 10
done
