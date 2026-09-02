#!/usr/bin/env bash
# sync-root.sh — the App-of-Apps pattern: one root app that syncs many children.
#
# The root Application declares an `apps` directory full of child *.app
# manifests. Syncing the root discovers each child and syncs it — so your whole
# fleet is declared in git and rolled out from a single entry point.
#
# Usage:
#   bash sync-root.sh --app ROOT_MANIFEST [--base DIR] [--dry-run] [--prune]
#
# Exit: 0 all synced · non-zero if any child errored or (in --dry-run) is OutOfSync
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day27-argo.log}" COMPONENT="sync-root"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/argo-lib.sh"

usage() {
  echo "usage: $0 --app ROOT_MANIFEST [--base DIR] [--dry-run] [--prune]" >&2
  exit 2
}

main() {
  local app="" base="." dry=0 prune=0
  local -a passthru=()
  while (($#)); do
    case "$1" in
      --app)
        app="${2:?}"
        shift
        ;;
      --base)
        base="${2:?}"
        shift
        ;;
      --dry-run)
        dry=1
        passthru+=(--dry-run)
        ;;
      --prune)
        prune=1
        passthru+=(--prune)
        ;;
      -h | --help) usage ;;
      -*)
        echo "unknown flag: $1" >&2
        usage
        ;;
      *) usage ;;
    esac
    shift
  done
  [[ -n "$app" ]] || usage
  require_file "$app" || return 1
  : "$dry" "$prune"

  local kind name apps_dir
  kind="$(app_get "$app" kind || true)"
  name="$(app_get "$app" name || true)"
  apps_dir="$(app_get "$app" apps || true)"
  [[ "$kind" == "Application" ]] || {
    log_error "unsupported kind: '${kind:-<none>}' (want Application)"
    return 1
  }
  [[ -n "$name" && -n "$apps_dir" ]] || {
    log_error "root Application needs name and apps"
    return 1
  }
  apps_dir="$base/$apps_dir"
  require_dir "$apps_dir" || return 1

  local child total=0 synced=0 rc=0 crc
  shopt -s nullglob
  for child in "$apps_dir"/*.app; do
    total=$((total + 1))
    echo ">>> syncing $(basename "$child")"
    crc=0
    bash "$SCRIPT_DIR/sync-app.sh" --app "$child" --base "$base" "${passthru[@]}" || crc=$?
    if ((crc == 0)); then
      synced=$((synced + 1))
    else
      rc=1
    fi
    echo
  done
  shopt -u nullglob

  ((total > 0)) || {
    log_error "no *.app children found in $apps_dir"
    return 1
  }

  echo "============================"
  printf 'root %s: %s/%s apps synced\n' "$name" "$synced" "$total"
  return "$rc"
}

main "$@"
