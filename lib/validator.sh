#!/usr/bin/env bash
# lib/validator.sh — precondition checks. Fail early with a clear message.
# Requires lib/logging.sh sourced first. Each returns 1 and logs on failure.
require_var() {
  local name rc=0
  for name in "$@"; do
    [[ -z "${!name:-}" ]] && {
      log_error "Required variable '$name' is unset or empty"
      rc=1
    }
  done
  return $rc
}
require_cmd() {
  local cmd rc=0
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || {
      log_error "Required command '$cmd' not found on PATH"
      rc=1
    }
  done
  return $rc
}
require_file() {
  local p="${1:-}"
  [[ -z "$p" ]] && {
    log_error "require_file called without a path"
    return 1
  }
  [[ -e "$p" ]] || {
    log_error "File does not exist: $p"
    return 1
  }
  [[ -f "$p" ]] || {
    log_error "Path exists but is not a regular file: $p"
    return 1
  }
}
require_dir() {
  local p="${1:-}"
  [[ -z "$p" ]] && {
    log_error "require_dir called without a path"
    return 1
  }
  [[ -e "$p" ]] || {
    log_error "Directory does not exist: $p"
    return 1
  }
  [[ -d "$p" ]] || {
    log_error "Path exists but is not a directory: $p"
    return 1
  }
}
require_int() {
  local name="${1:-}"
  require_var "$name" || return 1
  [[ "${!name}" =~ ^[0-9]+$ ]] || {
    log_error "Variable '$name' must be a non-negative integer, got: ${!name}"
    return 1
  }
}
require_safe_path() {
  local p="${1:-}"
  [[ -z "$p" ]] && {
    log_error "Refusing to operate on an empty path"
    return 1
  }
  [[ "$p" == "/" ]] && {
    log_error "Refusing to operate on filesystem root"
    return 1
  }
  [[ "$p" == *".."* ]] && {
    log_error "Refusing path containing '..': $p"
    return 1
  }
  return 0
}
