#!/usr/bin/env bash
set -euo pipefail

SERVICE="nginx"
ALERT_EMAIL="admin@example.com"
LOG="/var/log/health-check.log"

log() {
  local level="$1"
  shift
  local msg
  msg="[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*"
  echo "$msg"
  echo "$msg" >>"$LOG" 2>/dev/null || echo "(warning: couldn't write to $LOG — check permissions)"
}

check_service() {
  if systemctl is-active --quiet "$SERVICE"; then
    log "OK" "$SERVICE is running"
    return 0
  else
    log "CRITICAL" "$SERVICE is stopped!"
    if command -v mail &>/dev/null; then
      echo "$SERVICE down on $(hostname) at $(date)" | mail -s "ALERT: $SERVICE DOWN" "$ALERT_EMAIL"
    else
      log "WARN" "'mail' not installed — alert email NOT sent"
    fi
    return 1
  fi
}

trap 'log "INFO" "Monitoring ended"' EXIT

if [[ "${1:-}" == "--once" ]]; then
  check_service || true
  exit 0
fi

log "INFO" "Monitoring started — checking $SERVICE every 30s (Ctrl+C to stop)"
while true; do
  check_service || true
  sleep 30
done
