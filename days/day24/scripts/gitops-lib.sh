#!/usr/bin/env bash
# gitops-lib.sh — shared helpers for declarative reconcile + drift detection.
#
# Model: DESIRED state is a directory (your git source of truth); LIVE state is
# the directory it should be reconciled to. Everything compares by content hash,
# so it's idempotent and order-independent.
#
# Note: uses pipes (not process substitution) so it runs on minimal shells.
set -euo pipefail

# List regular files in a dir as sorted, dir-relative paths.
list_files() {
  local dir="${1:?dir required}"
  (cd "$dir" && find . -type f | sed 's|^\./||' | sort)
}

# Content hash of a single file.
file_hash() {
  sha256sum "${1:?file required}" | awk '{print $1}'
}

# Emit the drift between DESIRED and LIVE, one finding per line:
#   MISSING<TAB>path   (in desired, absent from live)
#   CHANGED<TAB>path   (present in both, different content)
#   EXTRA<TAB>path     (in live, not declared in desired)
diff_state() {
  local desired="${1:?}" live="${2:?}" f dh lh
  list_files "$desired" | while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ ! -f "$live/$f" ]]; then
      printf 'MISSING\t%s\n' "$f"
    else
      dh="$(file_hash "$desired/$f")"
      lh="$(file_hash "$live/$f")"
      [[ "$dh" != "$lh" ]] && printf 'CHANGED\t%s\n' "$f"
    fi
  done
  list_files "$live" | while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ ! -f "$desired/$f" ]] && printf 'EXTRA\t%s\n' "$f"
  done
}
