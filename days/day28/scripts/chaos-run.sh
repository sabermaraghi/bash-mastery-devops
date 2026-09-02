#!/usr/bin/env bash
# chaos-run.sh — a full chaos experiment: hypothesis → inject → heal → verify.
#
# The scientific loop of chaos engineering:
#   1. STEADY STATE  — assert the system is healthy (the hypothesis baseline)
#   2. INJECT        — cause a controlled fault (chaos-kill)
#   3. HEAL          — give the system a chance to recover (--heal-cmd)
#   4. VERIFY        — assert steady state is restored
# The experiment PASSES only if the system returns to steady state.
#
# Usage:
#   bash chaos-run.sh --state-dir DIR --name NAME --expect E \
#        [--count N] [--seed S] [--heal-cmd "CMD"] [--dry-run]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day28-chaos.log}" COMPONENT="chaos-run"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/chaos-lib.sh"

usage() {
  echo "usage: $0 --state-dir DIR --name NAME --expect E [--count N] [--seed S] [--heal-cmd CMD] [--dry-run]" >&2
  exit 2
}

main() {
  local state="" name="" expect="" count="1" seed="1" heal="" dry=0
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
      --seed)
        seed="${2:?}"
        shift
        ;;
      --heal-cmd)
        heal="${2:?}"
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

  local pods_dir="$state/pods" obs

  # 1. steady state (hypothesis baseline)
  obs="$(count_pods "$pods_dir" "$name")"
  echo "[1/4] steady state: observed=$obs expected=$expect"
  if ((obs != expect)); then
    echo "ABORT: not in steady state before experiment"
    log_error "experiment aborted — baseline not steady ($obs/$expect)"
    return 1
  fi

  # 2. inject
  echo "[2/4] injecting fault (count=$count seed=$seed)"
  local kill_args=(--state-dir "$state" --name "$name" --expect "$expect" --count "$count" --seed "$seed")
  ((dry)) && kill_args+=(--dry-run)
  bash "$SCRIPT_DIR/chaos-kill.sh" "${kill_args[@]}" || {
    log_error "fault injection failed"
    return 1
  }

  if ((dry)); then
    echo "[dry-run] skipping heal/verify"
    return 0
  fi

  # 3. heal
  if [[ -n "$heal" ]]; then
    echo "[3/4] healing: $heal"
    bash -c "$heal" || log_warn "heal command returned non-zero"
  else
    echo "[3/4] no --heal-cmd given (observing natural recovery)"
  fi

  # 4. verify
  obs="$(count_pods "$pods_dir" "$name")"
  echo "[4/4] verify: observed=$obs expected=$expect"
  echo "----------------------------"
  if ((obs == expect)); then
    echo "EXPERIMENT PASSED: system recovered to steady state"
    return 0
  fi
  echo "EXPERIMENT FAILED: system did not recover ($obs/$expect)"
  log_error "experiment failed — no recovery ($obs/$expect)"
  return 1
}

main "$@"
