#!/usr/bin/env bash
# deploy-guard.sh — the last zero-trust gate: authorize a deploy only when every
# precondition is independently verified. Fail-closed — deny unless all pass.
#
# Reads (all validated before use):
#   DEPLOY_ENV     one of: dev | staging | prod         (allowlist)
#   TARGET_HOST    must appear in ALLOWED_HOSTS          (allowlist)
#   ALLOWED_HOSTS  comma-separated allowlist of hosts
#   ARTIFACT_DIR   directory that must exist AND pass checksum verification
#
# Exit 0 + "DEPLOY AUTHORIZED" only when all checks pass; else 1 + reason.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day18-deploy.log}" COMPONENT="deploy-guard"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"

VERIFIER="$SCRIPT_DIR/verify-artifact.sh"

check_env() {
  require_var DEPLOY_ENV || return 1
  case "$DEPLOY_ENV" in
    dev | staging | prod) log_info "env allowed: $DEPLOY_ENV" ;;
    *)
      log_error "env not allowed: '$DEPLOY_ENV' (dev|staging|prod)"
      return 1
      ;;
  esac
}

check_host() {
  require_var TARGET_HOST ALLOWED_HOSTS || return 1
  local h
  IFS=',' read -ra _allow <<<"$ALLOWED_HOSTS"
  for h in "${_allow[@]}"; do
    [[ "$h" == "$TARGET_HOST" ]] && {
      log_info "host on allowlist: $TARGET_HOST"
      return 0
    }
  done
  log_error "host NOT on allowlist: $TARGET_HOST"
  return 1
}

check_artifact() {
  require_var ARTIFACT_DIR || return 1
  require_safe_path "$ARTIFACT_DIR" || return 1
  require_dir "$ARTIFACT_DIR" || return 1
  if bash "$VERIFIER" verify "$ARTIFACT_DIR" >/dev/null 2>&1; then
    log_info "artifact integrity verified: $ARTIFACT_DIR"
    return 0
  fi
  log_error "artifact failed integrity check: $ARTIFACT_DIR"
  return 1
}

main() {
  log_info "== deploy-guard: verifying preconditions =="
  local ok=0
  check_env || ok=1
  check_host || ok=1
  check_artifact || ok=1
  if ((ok != 0)); then
    log_error "DEPLOY BLOCKED — one or more checks failed (fail-closed)"
    return 1
  fi
  log_info "DEPLOY AUTHORIZED — $DEPLOY_ENV @ $TARGET_HOST"
  echo "DEPLOY AUTHORIZED"
  return 0
}

main "$@"
