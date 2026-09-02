#!/usr/bin/env bash
# sync-app.sh — sync one leaf Application: reconcile its git source to its dest.
#
# Reports Sync status (Synced / OutOfSync) and Health, just like `argocd app
# sync`. Idempotent. Unmanaged extra files are left alone unless --prune.
#
# Usage:
#   bash sync-app.sh --app MANIFEST [--base DIR] [--dry-run] [--prune]
#
# Exit: 0 synced/applied · 3 dry-run OutOfSync · 1/2 error
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day27-argo.log}" COMPONENT="sync-app"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/argo-lib.sh"

usage() {
  echo "usage: $0 --app MANIFEST [--base DIR] [--dry-run] [--prune]" >&2
  exit 2
}

# count drift that matters: MISSING + CHANGED always; EXTRA only when pruning.
_drift_count() {
  local changes="$1" prune="$2" n=0
  [[ -z "$changes" ]] && {
    printf 0
    return
  }
  n=$(printf '%s\n' "$changes" | grep -cE '^(MISSING|CHANGED)\b' || true)
  if ((prune)); then
    n=$((n + $(printf '%s\n' "$changes" | grep -cE '^EXTRA\b' || true)))
  fi
  printf '%s' "$n"
}

main() {
  local app="" base="." dry=0 prune=0
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
      --dry-run) dry=1 ;;
      --prune) prune=1 ;;
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

  local kind name source dest
  kind="$(app_get "$app" kind || true)"
  name="$(app_get "$app" name || true)"
  [[ "$kind" == "Application" ]] || {
    log_error "unsupported kind: '${kind:-<none>}' (want Application)"
    return 1
  }
  [[ -n "$name" ]] || {
    log_error "Application missing name"
    return 1
  }
  if app_get "$app" apps >/dev/null 2>&1; then
    log_error "'$name' is an app-of-apps — use sync-root.sh"
    return 1
  fi
  source="$(app_get "$app" source || true)"
  dest="$(app_get "$app" dest || true)"
  [[ -n "$source" && -n "$dest" ]] || {
    log_error "leaf Application needs source and dest"
    return 1
  }
  source="$base/$source"
  dest="$base/$dest"
  require_dir "$source" || return 1

  local changes drift
  changes="$(diff_dirs "$source" "$dest")" || true
  drift="$(_drift_count "$changes" "$prune")"

  local status line st f
  if ((dry)); then
    if [[ -n "$changes" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        st="${line%%$'\t'*}"
        f="${line#*$'\t'}"
        case "$st" in
          MISSING) echo "CREATE	$f" ;;
          CHANGED) echo "UPDATE	$f" ;;
          EXTRA) ((prune)) && echo "PRUNE	$f" || echo "IGNORE	$f" ;;
        esac
      done <<<"$changes"
    fi
    ((drift > 0)) && status="OutOfSync" || status="Synced"
    echo "----------------------------"
    echo "app ${name}: ${status} (dry-run, ${drift} diff(s))"
    ((drift > 0)) && return 3
    return 0
  fi

  # apply
  mkdir -p "$dest"
  if [[ -n "$changes" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      st="${line%%$'\t'*}"
      f="${line#*$'\t'}"
      case "$st" in
        MISSING)
          echo "CREATE	$f"
          mkdir -p "$dest/$(dirname "$f")"
          cp "$source/$f" "$dest/$f"
          ;;
        CHANGED)
          echo "UPDATE	$f"
          mkdir -p "$dest/$(dirname "$f")"
          cp "$source/$f" "$dest/$f"
          ;;
        EXTRA)
          if ((prune)); then
            echo "PRUNE	$f"
            rm -f "$dest/$f"
          else
            echo "IGNORE	$f (use --prune to remove)"
          fi
          ;;
      esac
    done <<<"$changes"
  fi

  # recompute post-apply status
  changes="$(diff_dirs "$source" "$dest")" || true
  drift="$(_drift_count "$changes" "$prune")"
  ((drift > 0)) && status="OutOfSync" || status="Synced"
  local health="Degraded"
  [[ "$status" == "Synced" ]] && health="Healthy"
  echo "----------------------------"
  echo "app ${name}: ${status} (${health})"
  return 0
}

main "$@"
