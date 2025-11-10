#!/usr/bin/env bash
# Structured JSON logger for production

readonly LOG_FILE="${LOG_FILE:-/var/log/bash-app.log}"

log() {
  local level="$1" message="$2" component="${3:-main}"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"timestamp":"%s","level":"%s","component":"%s","message":"%s"}\n' \
    "$timestamp" "$level" "$component" "$message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1" "${COMPONENT:-unknown}"; }
log_error() { log "ERROR" "$1" "${COMPONENT:-unknown}"; }
log_debug() { [[ "${DEBUG:-false}" == "true" ]] && log "DEBUG" "$1" "${COMPONENT:-unknown}"; }
