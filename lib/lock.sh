#!/usr/bin/env bash
# lib/lock.sh — single-instance guard using flock on FD 200.
_LOCK_HELD=0
acquire_lock() {
  local lockfile="${LOCK_FILE:-/tmp/$(basename "$0").lock}"
  exec 200>"$lockfile"
  if ! flock -n 200; then
    log_error "Another instance is running (lock: $lockfile)"
    exit 1
  fi
  _LOCK_HELD=1
  echo $$ >&200
  trap release_lock EXIT INT TERM
}
release_lock() {
  [[ "${_LOCK_HELD:-0}" == 1 ]] || return 0
  flock -u 200 2>/dev/null || true
  _LOCK_HELD=0
}
