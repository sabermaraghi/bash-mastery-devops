#!/usr/bin/env bash
# heal.sh — one self-healing pass: probe every pod, remediate the dead ones.
#
# For each of replicas 0..N-1:
#   alive         -> leave it, reset its restart counter
#   dead + budget -> RESTART (recreate with desired image), bump counter
#   dead + over   -> CrashLoopBackOff (give up on that pod)
# Restart policy: Never = report only; OnFailure/Always = restart dead pods.
# A :bad image never comes back alive, so it climbs to CrashLoopBackOff — just
# like a real crashing container.
#
# Usage:
#   bash heal.sh --state-dir DIR --name NAME --replicas N --image IMG \
#        [--restart-policy Always|OnFailure|Never] [--max-restarts M] [--dry-run]
# Exit: 0 all replicas healthy after the pass · 1 still degraded
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day29-heal.log}" COMPONENT="heal"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/health-lib.sh"

usage() {
  echo "usage: $0 --state-dir DIR --name NAME --replicas N --image IMG [--restart-policy Always|OnFailure|Never] [--max-restarts M] [--dry-run]" >&2
  exit 2
}

main() {
  local state="" name="" replicas="" image="" policy="Always" max=5 dry=0
  while (($#)); do
    case "$1" in
      --state-dir)
        state="${2:?}"
        shift
        ;;
      --name)
        name="${2:?}"
        shift
        ;;
      --replicas)
        replicas="${2:?}"
        shift
        ;;
      --image)
        image="${2:?}"
        shift
        ;;
      --restart-policy)
        policy="${2:?}"
        shift
        ;;
      --max-restarts)
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
  [[ -n "$state" && -n "$name" && -n "$replicas" && -n "$image" ]] || usage
  is_int "$replicas" || {
    log_error "--replicas must be a non-negative integer: $replicas"
    return 1
  }
  is_int "$max" || {
    log_error "--max-restarts must be a non-negative integer: $max"
    return 1
  }
  case "$policy" in
    Always | OnFailure | Never) ;;
    *)
      log_error "--restart-policy must be Always, OnFailure or Never: $policy"
      return 1
      ;;
  esac

  local pods_dir="$state/pods" rst_dir="$state/restarts"
  ((dry)) || mkdir -p "$pods_dir" "$rst_dir"

  local i pod pn rfile rc restarted=0 crashloop=0 degraded=0 alive=0
  for ((i = 0; i < replicas; i++)); do
    pn="${name}-${i}"
    pod="$pods_dir/$pn"
    rfile="$rst_dir/$pn"
    if probe_pod "$pod"; then
      alive=$((alive + 1))
      ((dry)) || rm -f "$rfile" # stable pod — reset backoff counter
      continue
    fi
    rc="$(restart_count "$rst_dir" "$pn")"
    if ((rc >= max)); then
      echo "CRASHLOOP $pn (restarts=$rc, giving up)"
      crashloop=$((crashloop + 1))
      continue
    fi
    if [[ "$policy" == "Never" ]]; then
      echo "UNHEALTHY $pn (policy=Never, not restarting)"
      degraded=$((degraded + 1))
      continue
    fi
    echo "RESTART $pn (attempt $((rc + 1))/$max, image=$image)"
    if ((dry == 0)); then
      printf '%s\n' "$image" >"$pod"
      printf '%s' "$((rc + 1))" >"$rfile"
    fi
    restarted=$((restarted + 1))
  done

  echo "----------------------------"
  if ((dry)); then
    printf 'plan: %s restart(s), %s crashloop, %s degraded\n' "$restarted" "$crashloop" "$degraded"
    return 0
  fi

  local hc
  hc="$(healthy_count "$pods_dir" "$name" "$replicas")"
  printf 'healed: %s restart(s), %s crashloop — healthy %s/%s\n' "$restarted" "$crashloop" "$hc" "$replicas"
  ((hc == replicas)) && return 0
  return 1
}

main "$@"
