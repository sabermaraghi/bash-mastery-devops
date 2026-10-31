#!/usr/bin/env bash
# lib/logging.sh — the one structured logger for the whole repo.
# Sourced by scripts and modules; never executed directly.
#
# COMPONENT tags each line so multi-module output stays greppable.
# LOG_FILE is overridable; if it isn't writable we fall back to stdout-only
# instead of letting `tee` fail the caller under `set -euo pipefail`.
LOG_FILE="${LOG_FILE:-/var/log/bash-mastery.log}"
if ! { [[ -w "$LOG_FILE" ]] ||
  { [[ ! -e "$LOG_FILE" ]] && [[ -w "$(dirname "$LOG_FILE")" ]]; }; }; then
  LOG_FILE="/dev/null"
fi

log() {
  local level="$1" message="$2" component="${3:-${COMPONENT:-main}}"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"timestamp":"%s","level":"%s","component":"%s","message":"%s"}\n' \
    "$ts" "$level" "$component" "$message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1" "${COMPONENT:-main}"; }
log_warn() { log "WARN" "$1" "${COMPONENT:-main}"; }
log_error() { log "ERROR" "$1" "${COMPONENT:-main}" >&2; }
log_debug() { [[ "${DEBUG:-false}" == "true" ]] && log "DEBUG" "$1" "${COMPONENT:-main}"; }
