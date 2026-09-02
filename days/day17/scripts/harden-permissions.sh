#!/usr/bin/env bash
# harden-permissions.sh — write secrets safely and audit a tree for weak modes.
#
# Subcommands:
#   write <file> <content>   create <file> with 0600 (owner read/write only),
#                            under a restrictive umask, creating parent dirs 0700
#   audit <dir>              report world-writable files/dirs and world/group
#                            readable files that look like secrets (.pem/.key/.env)
#
# Exit codes: audit returns 1 if any finding is reported, else 0.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day17-perms.log}" COMPONENT="harden-perms"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"

write_secret() {
  local file="${1:?file required}" content="${2:-}"
  umask 077 # new files -> 0600, new dirs -> 0700
  local dir
  dir="$(dirname "$file")"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  printf '%s\n' "$content" >"$file"
  chmod 600 "$file" # explicit, in case the file pre-existed
  log_info "wrote $file with mode $(stat -c '%a' "$file")"
}

audit() {
  local dir="${1:?dir required}"
  [[ -d "$dir" ]] || {
    log_error "not a directory: $dir"
    return 2
  }
  local findings=0 tmp
  tmp="$(mktemp)"
  trap 'rm -f "${tmp:-}"' RETURN

  # world-writable files or directories are always a problem
  find "$dir" -perm -o+w ! -type l >"$tmp" 2>/dev/null || true
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    echo "WORLD-WRITABLE: $p ($(stat -c '%a' "$p"))"
    findings=$((findings + 1))
  done <"$tmp"

  # secret-looking files that are readable by group or other
  find "$dir" -type f \( -name '*.pem' -o -name '*.key' -o -name '.env' \) \
    \( -perm /o+r -o -perm /g+r \) >"$tmp" 2>/dev/null || true
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    echo "SECRET TOO OPEN: $p ($(stat -c '%a' "$p"))"
    findings=$((findings + 1))
  done <"$tmp"

  if ((findings > 0)); then
    log_error "permission audit found $findings issue(s)"
    return 1
  fi
  log_info "permission audit clean: $dir"
  return 0
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    write) write_secret "$@" ;;
    audit) audit "$@" ;;
    *)
      echo "usage: $0 {write <file> <content> | audit <dir>}" >&2
      return 2
      ;;
  esac
}

main "$@"
