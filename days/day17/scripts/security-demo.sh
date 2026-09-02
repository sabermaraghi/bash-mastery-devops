#!/usr/bin/env bash
# Security fundamentals, demonstrated on a small, safe example:
#   1. strict mode + a locked-down IFS
#   2. allowlist validation instead of blocklists
#   3. safe integer / path handling via lib/validator.sh
#   4. why quoting matters (word-splitting & glob injection)
#   5. a safe alternative to `eval`
#   6. secure temp files with mktemp + cleanup trap
set -euo pipefail
IFS=$'\n\t' # drop space from IFS: avoids surprise word-splitting on spaces
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day17-demo.log}" COMPONENT="day17"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"

# 2. Allowlist validation: only known-good values pass. Everything else is denied
#    by default, which is far safer than trying to enumerate bad values.
validate_env() {
  local env="$1"
  case "$env" in
    dev | staging | prod) return 0 ;;
    *)
      log_error "rejected environment: '$env' (allowed: dev|staging|prod)"
      return 1
      ;;
  esac
}

# 5. A safe alternative to eval: dispatch by name through a case, so attacker
#    input can never become executed code.
run_action() {
  local action="$1"
  case "$action" in
    status) echo "service: ok" ;;
    version) echo "v1.0.0" ;;
    *)
      log_error "unknown action: '$action'"
      return 1
      ;;
  esac
}

main() {
  log_info "== security fundamentals demo =="

  # 3. Validate untrusted input BEFORE using it.
  validate_env "staging"
  log_info "environment accepted: staging"
  validate_env "rm -rf /" || log_info "malicious environment correctly denied"

  local port="8080"
  PORT_VAL="$port" require_int PORT_VAL && log_info "port is a valid integer: $port"

  # require_safe_path rejects empty, '/', and '..' traversal.
  require_safe_path "/srv/app/config" && log_info "path is safe: /srv/app/config"
  require_safe_path "../../etc/passwd" || log_info "path traversal correctly denied"

  # 4. Quoting: an unquoted variable is split on IFS and glob-expanded.
  local danger='* ; rm'
  echo "quoted (safe):   [$danger]"
  log_info "never pass unquoted user input to a command"

  # 5. Safe dispatch instead of eval "$user_input".
  run_action status
  run_action "; reboot" || log_info "injected action correctly denied"

  # 6. Secure temp file: unpredictable name, cleaned up on exit.
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/day17.XXXXXXXX")"
  trap 'rm -f "${tmp:-}"' EXIT
  umask 077 # anything we create is owner-only
  printf 'transient secret\n' >"$tmp"
  log_info "wrote secure temp file: $tmp (perms $(stat -c '%a' "$tmp" 2>/dev/null || echo n/a))"

  log_info "== done =="
}

main "$@"
