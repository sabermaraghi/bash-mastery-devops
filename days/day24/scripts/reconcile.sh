#!/usr/bin/env bash
# reconcile.sh — converge a LIVE directory to a DESIRED (git) directory.
#
# The heart of GitOps: declare what you want, and let the reconciler make the
# world match. Idempotent — running it twice with no upstream change is a no-op.
#
# Actions: CREATE (missing), UPDATE (drifted), PRUNE (extra, only with --prune).
#
# Usage:
#   bash reconcile.sh [--dry-run] [--prune] DESIRED_DIR LIVE_DIR
#     --dry-run  plan only; report actions without touching LIVE
#     --prune    delete files in LIVE that aren't declared in DESIRED
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day24-reconcile.log}" COMPONENT="reconcile"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/gitops-lib.sh"

usage() {
  echo "usage: $0 [--dry-run] [--prune] DESIRED_DIR LIVE_DIR" >&2
  exit 2
}

main() {
  local dry=0 prune=0
  local -a pos=()
  while (($#)); do
    case "$1" in
      --dry-run) dry=1 ;;
      --prune) prune=1 ;;
      -h | --help) usage ;;
      -*)
        echo "unknown flag: $1" >&2
        usage
        ;;
      *) pos+=("$1") ;;
    esac
    shift
  done
  ((${#pos[@]} == 2)) || usage
  local desired="${pos[0]}" live="${pos[1]}"
  require_dir "$desired" || return 1
  # LIVE may not exist yet on a first apply — create it (unless dry-run).
  if [[ ! -d "$live" ]]; then
    ((dry)) || mkdir -p "$live"
  fi

  local changes status f created=0 updated=0 pruned=0
  changes="$(diff_state "$desired" "$live")" || true

  if [[ -n "$changes" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      status="${line%%$'\t'*}"
      f="${line#*$'\t'}"
      case "$status" in
        MISSING)
          echo "CREATE	$f"
          created=$((created + 1))
          if ((dry == 0)); then
            mkdir -p "$live/$(dirname "$f")"
            cp "$desired/$f" "$live/$f"
          fi
          ;;
        CHANGED)
          echo "UPDATE	$f"
          updated=$((updated + 1))
          if ((dry == 0)); then
            mkdir -p "$live/$(dirname "$f")"
            cp "$desired/$f" "$live/$f"
          fi
          ;;
        EXTRA)
          if ((prune)); then
            echo "PRUNE	$f"
            pruned=$((pruned + 1))
            ((dry == 0)) && rm -f "$live/$f"
          else
            echo "IGNORE	$f (use --prune to remove)"
          fi
          ;;
      esac
    done <<<"$changes"
  fi

  echo "----------------------------"
  if ((created == 0 && updated == 0 && pruned == 0)); then
    echo "already in sync"
  else
    local mode="applied"
    ((dry)) && mode="planned"
    printf '%s: %s created, %s updated, %s pruned\n' "$mode" "$created" "$updated" "$pruned"
  fi
}

main "$@"
