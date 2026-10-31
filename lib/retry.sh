#!/usr/bin/env bash
# lib/retry.sh — retry a command with exponential backoff.
# Usage: retry <max_attempts> <delay_seconds> <command> [args...]
retry() {
  local max_attempts=${1:-3} delay=${2:-2} attempt=1
  shift 2
  while ((attempt <= max_attempts)); do
    "$@" && return 0
    log_warn "Attempt $attempt/$max_attempts failed. Retrying in ${delay}s..."
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
  log_error "All $max_attempts attempts failed"
  return 1
}
