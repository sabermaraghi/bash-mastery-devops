#!/usr/bin/env bash
# argo-lib.sh — shared helpers for a mini ArgoCD-style GitOps CD (sourced).
#
# An Application is a key=value manifest. A LEAF app maps a git source dir to a
# live dest dir:
#   kind   = Application
#   name   = frontend
#   source = apps/frontend        # desired (git)
#   dest   = live/frontend        # where it's synced
#
# A ROOT app (app-of-apps) points at a directory of child *.app manifests:
#   kind = Application
#   name = root
#   apps = apps/                  # dir of child Application manifests
#
# Paths are resolved relative to --base (default: cwd). Sync compares by
# SHA-256, so it's idempotent and order-independent. Pipes only (no procsub).
set -euo pipefail

_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# app_get <manifest> <key> — print value for key, or return 1 if absent.
app_get() {
  local file="${1:?manifest required}" key="${2:?key required}" line k
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(_trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || continue
    k="$(_trim "${line%%=*}")"
    if [[ "$k" == "$key" ]]; then
      _trim "${line#*=}"
      return 0
    fi
  done <"$file"
  return 1
}

list_files() {
  local dir="${1:?}"
  (cd "$dir" && find . -type f | sed 's|^\./||' | sort)
}

file_hash() { sha256sum "${1:?}" | awk '{print $1}'; }

# diff_dirs <desired> <live> — emit drift as: MISSING|CHANGED|EXTRA<TAB>path
diff_dirs() {
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
  [[ -d "$live" ]] || return 0
  list_files "$live" | while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ ! -f "$desired/$f" ]] && printf 'EXTRA\t%s\n' "$f"
  done
}
