#!/usr/bin/env bash
# operator.sh — the control loop: watch a dir of CRs and reconcile each.
#
# Real operators run forever, waking on events or a resync interval. This one
# does the same shape: reconcile every *.cr in a directory, then either exit
# (--once) or sleep and repeat (--interval). --max-iterations bounds the loop
# so it's safe to run in tests/CI.
#
# Usage:
#   bash operator.sh --cr-dir DIR --state-dir DIR [--once] \
#        [--interval SECONDS] [--max-iterations N] [--dry-run]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day26-operator.log}" COMPONENT="operator"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"

usage() {
  echo "usage: $0 --cr-dir DIR --state-dir DIR [--once] [--interval N] [--max-iterations N] [--dry-run]" >&2
  exit 2
}

main() {
  local cr_dir="" state="" once=0 interval=5 max=0 dry=0
  while (($#)); do
    case "$1" in
      --cr-dir)
        cr_dir="${2:?}"
        shift
        ;;
      --state-dir)
        state="${2:?}"
        shift
        ;;
      --once) once=1 ;;
      --interval)
        interval="${2:?}"
        shift
        ;;
      --max-iterations)
        max="${2:?}"
        shift
        ;;
      --dry-run) dry=1 ;;
      -h | --help) usage ;;
      -*)
        echo "unknown flag: $1" >&2
        usage
        ;;
      *) usage ;;
    esac
    shift
  done
  [[ -n "$cr_dir" && -n "$state" ]] || usage
  require_dir "$cr_dir" || return 1

  local iter=0 cr found rc=0
  while true; do
    iter=$((iter + 1))
    found=0
    shopt -s nullglob
    for cr in "$cr_dir"/*.cr; do
      found=1
      log_info "reconciling $(basename "$cr") (iteration $iter)"
      if ((dry)); then
        bash "$SCRIPT_DIR/reconcile-cr.sh" --cr "$cr" --state-dir "$state" --dry-run || rc=$?
      else
        bash "$SCRIPT_DIR/reconcile-cr.sh" --cr "$cr" --state-dir "$state" || rc=$?
      fi
    done
    shopt -u nullglob
    ((found)) || log_warn "no *.cr manifests found in $cr_dir"

    ((once)) && break
    ((max > 0 && iter >= max)) && break
    sleep "$interval"
  done
  return "$rc"
}

main "$@"
