#!/usr/bin/env bash
# watchdog.sh — the self-healing control loop.
#
# Repeatedly runs a heal pass until the system is healthy or the iteration
# budget runs out. This is what turns Day 28's *failed* chaos experiment into a
# passing one: kill some pods, point the watchdog at them, and it converges the
# system back to steady state — unless an image is genuinely broken, in which
# case it stops at CrashLoopBackOff instead of restarting forever.
#
# Usage:
#   bash watchdog.sh --state-dir DIR --name NAME --replicas N --image IMG \
#        [--restart-policy P] [--max-restarts M] [--once | --max-iterations K] \
#        [--interval SECONDS] [--dry-run]
# Exit: 0 converged to healthy · 1 still degraded when the budget ran out
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day29-heal.log}" COMPONENT="watchdog"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/health-lib.sh"

usage() {
  echo "usage: $0 --state-dir DIR --name NAME --replicas N --image IMG [--restart-policy P] [--max-restarts M] [--once | --max-iterations K] [--interval S] [--dry-run]" >&2
  exit 2
}

main() {
  local state="" name="" replicas="" image="" max_iter=10 interval=0 once=0
  local -a heal_args=()
  while (($#)); do
    case "$1" in
      --state-dir)
        state="${2:?}"
        heal_args+=(--state-dir "$2")
        shift
        ;;
      --name)
        name="${2:?}"
        heal_args+=(--name "$2")
        shift
        ;;
      --replicas)
        replicas="${2:?}"
        heal_args+=(--replicas "$2")
        shift
        ;;
      --image)
        image="${2:?}"
        heal_args+=(--image "$2")
        shift
        ;;
      --restart-policy)
        heal_args+=(--restart-policy "${2:?}")
        shift
        ;;
      --max-restarts)
        heal_args+=(--max-restarts "${2:?}")
        shift
        ;;
      --dry-run) heal_args+=(--dry-run) ;;
      --once) once=1 ;;
      --max-iterations)
        max_iter="${2:?}"
        shift
        ;;
      --interval)
        interval="${2:?}"
        shift
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
  [[ -n "$state" && -n "$name" && -n "$replicas" && -n "$image" ]] || usage
  ((once)) && max_iter=1

  local iter=0 rc=0
  while ((iter < max_iter)); do
    iter=$((iter + 1))
    echo "=== watchdog pass $iter/$max_iter ==="
    rc=0
    bash "$SCRIPT_DIR/heal.sh" "${heal_args[@]}" || rc=$?
    if ((rc == 0)); then
      echo "watchdog: system healthy after $iter pass(es)"
      return 0
    fi
    ((interval > 0 && iter < max_iter)) && sleep "$interval"
  done

  echo "watchdog: system still degraded after $iter pass(es)"
  return 1
}

main "$@"
