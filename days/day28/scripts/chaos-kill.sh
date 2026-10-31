#!/usr/bin/env bash
# chaos-kill.sh — inject a controlled fault: delete some of an app's pods.
#
# Safe by construction:
#   - refuses to run unless the app is in steady state (--expect)
#   - never exceeds the blast radius (--max-percent, default 50)
#   - deterministic victims for a given --seed (reproducible)
#   - --dry-run reports victims without touching anything
#
# Usage:
#   bash chaos-kill.sh --state-dir DIR --name NAME --expect E \
#        [--count N | --percent P] [--seed S] [--max-percent M] [--dry-run]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day28-chaos.log}" COMPONENT="chaos-kill"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/chaos-lib.sh"

usage() {
  echo "usage: $0 --state-dir DIR --name NAME --expect E [--count N | --percent P] [--seed S] [--max-percent M] [--dry-run]" >&2
  exit 2
}

main() {
  local state="" name="" expect="" count="" percent="" seed="1" max_pct=50 dry=0
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
      --expect)
        expect="${2:?}"
        shift
        ;;
      --count)
        count="${2:?}"
        shift
        ;;
      --percent)
        percent="${2:?}"
        shift
        ;;
      --seed)
        seed="${2:?}"
        shift
        ;;
      --max-percent)
        max_pct="${2:?}"
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
  [[ -n "$state" && -n "$name" && -n "$expect" ]] || usage
  is_int "$expect" || {
    log_error "--expect must be a non-negative integer: $expect"
    return 1
  }

  local pods_dir="$state/pods" total
  total="$(count_pods "$pods_dir" "$name")"

  # RULE 1 — steady state first.
  if ((total != expect)); then
    log_error "not in steady state: observed=$total expected=$expect — refusing to inject"
    return 1
  fi
  log_info "steady state verified: $total/$expect pods healthy"

  # resolve how many to kill
  local requested
  if [[ -n "$count" ]]; then
    is_int "$count" || {
      log_error "--count must be a non-negative integer: $count"
      return 1
    }
    requested="$count"
  elif [[ -n "$percent" ]]; then
    is_int "$percent" || {
      log_error "--percent must be a non-negative integer: $percent"
      return 1
    }
    requested=$(awk -v t="$total" -v p="$percent" 'BEGIN{v=t*p/100; printf "%d", (v==int(v)?v:int(v)+1)}')
  else
    requested=1
  fi
  ((requested >= 1)) || {
    log_error "nothing to kill (requested=$requested)"
    return 1
  }
  ((requested <= total)) || {
    log_error "requested $requested > $total existing pods"
    return 1
  }

  # RULE 2 — blast radius.
  local cap
  cap="$(blast_cap "$total" "$max_pct")"
  if ((requested > cap)); then
    log_error "blast radius exceeded: $requested > cap $cap (${max_pct}% of $total) — raise --max-percent to override"
    return 1
  fi

  # RULE 3 — deterministic victims.
  local victims v killed=0
  victims="$(pick_victims "$pods_dir" "$name" "$requested" "$seed")"
  while IFS= read -r v; do
    [[ -z "$v" ]] && continue
    echo "KILL $v"
    killed=$((killed + 1))
    ((dry)) || rm -f "$pods_dir/$v"
  done <<<"$victims"

  echo "----------------------------"
  local mode="injected"
  ((dry)) && mode="planned"
  printf '%s: killed %s/%s pods (blast cap %s, seed %s)\n' "$mode" "$killed" "$total" "$cap" "$seed"
}

main "$@"
