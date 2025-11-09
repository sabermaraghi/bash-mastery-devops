#!/bin/bash
set -euo pipefail

SERVICE="nginx"
ALERT_EMAIL="admin@example.com"
LOG="/var/log/health-check.log"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

check_service() {
  if systemctl is-active --quiet "$SERVICE"; then
    log "OK: $SERVICE is running"
    return 0
  else
    log "CRITICAL: $SERVICE is stopped!"
    echo "$SERVICE down on $(hostname) at $(date)" | mail -s "ALERT: $SERVICE DOWN" "$ALERT_EMAIL"
    return 1
  fi
}

trap 'log "INFO" "Monitoring ended"' EXIT

while true; do
  check_service || true
  sleep 30
done
