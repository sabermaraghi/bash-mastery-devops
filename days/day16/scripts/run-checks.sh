#!/usr/bin/env bash
# The same gate pre-commit runs, as a script - skips tools that aren't installed
# so it's safe to run anywhere.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

fail=0
_tmp="$(mktemp)"
find days lib -name '*.sh' >"$_tmp"
mapfile -t scripts <"$_tmp"
rm -f "$_tmp"

echo "== syntax (bash -n) =="
for s in "${scripts[@]}"; do
  bash -n "$s" || {
    echo "  SYNTAX FAIL: $s"
    fail=1
  }
done
echo "  checked ${#scripts[@]} scripts"

echo "== shfmt =="
if command -v shfmt >/dev/null 2>&1; then
  shfmt -d -i 2 -ci "${scripts[@]}" || fail=1
else echo "  SKIP - shfmt not installed"; fi

echo "== shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x --severity=error "${scripts[@]}" || fail=1
else echo "  SKIP - shellcheck not installed"; fi

echo "== gitleaks =="
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --no-git --no-banner || fail=1
else echo "  SKIP - gitleaks not installed"; fi

if ((fail == 0)); then
  echo "ALL CHECKS PASSED"
else
  echo "SOME CHECKS FAILED"
  exit 1
fi
