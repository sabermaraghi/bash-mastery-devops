#!/usr/bin/env bash
# real-scan.sh — Day 17, Option 2 (REAL): scan a path with real security tools.
#
# The offline default is secret-scanner.sh (a dependency-free regex engine).
# This runs the industry tools that engine imitates:
#   • gitleaks  — secret detection
#   • trivy fs  — secret + vulnerability + misconfig scanning
#
# Usage:
#   bash real-scan.sh [--dir DIR] [--secrets-only] [--no-git]
#     --dir DIR        path to scan (default: repo root)
#     --secrets-only   run only the secret scanner (skip trivy vuln/misconfig)
#     --no-git         scan only the current working tree, not git history
#                      (gitleaks scans all commits by default; use this to
#                       ignore secrets that live only in old/inherited history)
#
# Requires gitleaks (and trivy unless --secrets-only). Missing tools -> a clear
# message and exit 3, so it never pretends to have scanned.
# Exit: 0 clean · 1 findings · 2 usage · 3 missing tools.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day17-real-scan.log}" COMPONENT="real-scan"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"

main() {
  local dir="$REPO_ROOT" secrets_only=0 no_git=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        dir="${2:?--dir needs a path}"
        shift 2
        ;;
      --secrets-only)
        secrets_only=1
        shift
        ;;
      --no-git)
        no_git=1
        shift
        ;;
      -h | --help)
        echo "usage: $0 [--dir DIR] [--secrets-only] [--no-git]"
        return 0
        ;;
      *)
        echo "unknown arg: $1" >&2
        return 2
        ;;
    esac
  done
  [[ -d "$dir" ]] || {
    log_error "not a directory: $dir"
    return 2
  }

  local need=(gitleaks)
  [[ "$secrets_only" -eq 0 ]] && need+=(trivy)
  rm_require_tools "${need[@]}" || return 3

  rm_banner "Day 17 — real secret & vulnerability scan"
  local rc=0

  # gitleaks scans full git history by default; --no-git limits it to the
  # current working-tree files (handy when old/inherited commits carry leaks).
  local gl=(detect --source "$dir" --no-banner --redact)
  [[ "$no_git" -eq 1 ]] && gl+=(--no-git)
  local scope="full history"
  [[ "$no_git" -eq 1 ]] && scope="working tree only"
  log_info "running gitleaks on $dir ($scope)"
  if gitleaks "${gl[@]}"; then
    log_info "gitleaks: no leaks found"
  else
    log_error "gitleaks: leaks detected"
    rc=1
  fi

  if [[ "$secrets_only" -eq 0 ]]; then
    log_info "running trivy fs on $dir"
    if trivy fs --scanners vuln,secret,misconfig --exit-code 1 --quiet "$dir"; then
      log_info "trivy: clean"
    else
      log_error "trivy: findings detected"
      rc=1
    fi
  fi

  if [[ "$rc" -eq 0 ]]; then
    log_info "real scan clean: $dir"
  else
    log_error "real scan FAILED: findings in $dir"
  fi
  return "$rc"
}

main "$@"
