#!/usr/bin/env bash
# secret-scanner.sh — a tiny, dependency-free secret scanner.
#
# Scans a directory tree for the most common hardcoded-credential patterns and
# prints every hit as  path:line: <type>. Exits 1 if anything is found, so it
# can be dropped straight into CI or a pre-commit hook.
#
# Usage:
#   bash secret-scanner.sh [DIR]      # DIR defaults to the current directory
#
# It skips .git and common vendor dirs, and treats *.example / *.sample files
# as safe templates.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day17-scanner.log}" COMPONENT="secret-scanner"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"

# name|regex pairs. Kept as extended-regex strings for grep -E.
PATTERNS=(
  "AWS Access Key|AKIA[0-9A-Z]{16}"
  "GitHub Token|ghp_[0-9A-Za-z]{36}"
  "Slack Token|xox[baprs]-[0-9A-Za-z-]{10,}"
  "Private Key|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----"
  "Generic Secret|(api[_-]?key|secret|token|password)[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9/+]{16,}"
)

scan() {
  local dir="${1:-.}"
  [[ -d "$dir" ]] || {
    log_error "not a directory: $dir"
    return 2
  }

  local found=0 name regex
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "${tmp:-}"' RETURN

  for entry in "${PATTERNS[@]}"; do
    name="${entry%%|*}"
    regex="${entry#*|}"
    # -I skips binaries; --exclude-dir keeps us out of noise and vendor trees.
    grep -rInE -e "$regex" "$dir" \
      --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor \
      --exclude='*.example' --exclude='*.sample' >"$tmp" 2>/dev/null || true
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      echo "${hit%%:*}: ${name}"
      found=$((found + 1))
    done <"$tmp"
  done

  if ((found > 0)); then
    log_error "secret scan FAILED: $found potential secret(s) found"
    return 1
  fi
  log_info "secret scan clean: no hardcoded secrets found in $dir"
  return 0
}

scan "${1:-.}"
