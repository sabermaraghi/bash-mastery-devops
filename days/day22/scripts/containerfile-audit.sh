#!/usr/bin/env bash
# containerfile-audit.sh — static linter for rootless/security anti-patterns.
#
# Scans a Containerfile/Dockerfile (no runtime needed) and flags issues that
# break rootless or reproducible builds. Exits non-zero if any VIOLATION found.
#
# Usage: bash containerfile-audit.sh <Containerfile>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day22-audit.log}" COMPONENT="cf-audit"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"

audit() {
  local file="${1:?file required}"
  require_file "$file" || return 1

  local violations=0 warnings=0 user_seen=0
  local line lc kw img u
  while IFS= read -r line || [[ -n "$line" ]]; do
    lc="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
    kw="${lc%% *}"
    case "$kw" in
      from)
        img="$(printf '%s' "$line" | awk '{print $2}')"
        if [[ "$img" != *:* && "$img" != *@sha256:* ]]; then
          echo "VIOLATION: FROM without a pinned tag: $img"
          violations=$((violations + 1))
        elif [[ "${img##*:}" == "latest" ]]; then
          echo "VIOLATION: FROM uses :latest: $img"
          violations=$((violations + 1))
        fi
        ;;
      user)
        user_seen=1
        u="$(printf '%s' "$line" | awk '{print $2}')"
        if [[ "$u" == "root" || "$u" == "0" ]]; then
          echo "VIOLATION: USER root (container runs privileged)"
          violations=$((violations + 1))
          user_seen=0
        fi
        ;;
      add)
        if printf '%s' "$lc" | grep -qE 'add[[:space:]]+https?://'; then
          echo "WARN: ADD with remote URL; prefer COPY + verified download: $line"
          warnings=$((warnings + 1))
        fi
        ;;
      env)
        if printf '%s' "$lc" | grep -qiE '(password|secret|api[_-]?key|token)='; then
          echo "VIOLATION: secret baked into an ENV layer: $line"
          violations=$((violations + 1))
        fi
        ;;
    esac
    if printf '%s' "$lc" | grep -qw 'sudo'; then
      echo "WARN: uses sudo inside the image: $line"
      warnings=$((warnings + 1))
    fi
  done <"$file"

  if ((user_seen == 0)); then
    echo "VIOLATION: no non-root USER instruction (defaults to root)"
    violations=$((violations + 1))
  fi

  echo "---"
  echo "violations: $violations  warnings: $warnings"
  ((violations == 0))
}

audit "$@"
