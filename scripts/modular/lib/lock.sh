#!/usr/bin/env bash
# Prevent concurrent execution

acquire_lock() {
  local lockfile="${LOCK_FILE:-/var/run/$(basename "$0").lock}"
  exec 200>"$lockfile"
  if ! flock -n 200; then
    log_error "Another instance is running (lock: $lockfile)"
    exit 1
  fi
  echo $$ >&200
}

release_lock() {
  flock -u 200
  rm -f "${LOCK_FILE:-/var/run/$(basename "$0").lock}"
}
trap release_lock EXIT
