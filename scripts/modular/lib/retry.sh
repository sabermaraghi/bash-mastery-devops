#!/usr/bin/env bash
# retry command with exponential backoff

retry() {
  local max_attempts=${1:-5}
  local delay=${2:-2}
  local attempt=1

  while (( attempt <= max_attempts )); do
    "$@" && return 0
    log_error "Attempt $attempt failed. Retrying in ${delay}s..."
    sleep "$delay"
    ((attempt++))
    delay=$((delay * 2))
  done

  log_error "All $max_attempts attempts failed"
  return 1
}
