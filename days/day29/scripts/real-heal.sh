#!/usr/bin/env bash
# real-heal.sh — Option 2 (real) for Day 29: self-healing on a live cluster.
#
# The offline scripts (heal.sh / watchdog.sh) imitate a control loop over the
# Day 26 "cluster" (pods are files). On a real cluster, Kubernetes already
# restarts dead containers — so a real watchdog's job is the part K8s does NOT
# do for you:
#   1. RECONCILE DRIFT   — if the Deployment's replica count was changed away
#                          from the desired value, scale it back.
#   2. SURFACE CRASHLOOPS— detect pods stuck in CrashLoopBackOff (or past a
#                          restart budget) that will never recover on their own.
#   3. CONVERGE          — loop until the Deployment reports all replicas ready,
#                          or the iteration budget runs out (degraded).
#
# This is the real-cluster analog of the offline watchdog and pairs with Day 28:
# kill pods with real-chaos.sh, then watch real-heal.sh (and K8s) drive the
# Deployment back to steady state.
#
# Reuses the Day 25 kubectl safety rails (kubectl-lib.sh) and the shared
# real-mode helpers (realmode.sh). Scaling is opt-in: without --apply the
# command only reports (safe by default on a real cluster).
#
# Subcommands:
#   heal  --context CTX --namespace NS --deployment NAME --replicas N
#         [--selector SEL] [--max-restarts M] [--apply] [--confirm]
#   watch --context CTX --namespace NS --deployment NAME --replicas N
#         [--selector SEL] [--max-restarts M] [--once | --max-iterations K]
#         [--interval SECONDS] [--apply] [--confirm]
#
# `heal` runs one reconcile pass; `watch` loops until the Deployment is healthy
# or the budget is spent. Both talk to the cluster and degrade gracefully
# (exit 3) when kubectl or the cluster is absent.
#
# Exit: 0 healthy/converged · 1 degraded or guard failure · 2 usage
#       · 3 missing tool / cluster unreachable.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SELF="${BASH_SOURCE[0]}"
export LOG_FILE="${LOG_FILE:-/tmp/day29-real-heal.log}" COMPONENT="real-heal"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/days/day25/scripts/kubectl-lib.sh"

usage() {
  cat >&2 <<'EOF'
usage:
  real-heal.sh heal  --context CTX --namespace NS --deployment NAME --replicas N \
       [--selector SEL] [--max-restarts M] [--apply] [--confirm]
  real-heal.sh watch --context CTX --namespace NS --deployment NAME --replicas N \
       [--selector SEL] [--max-restarts M] [--once | --max-iterations K] \
       [--interval SECONDS] [--apply] [--confirm]
EOF
  exit 2
}

is_int() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

# Fail fast (exit 3) when the cluster can't be reached with this context.
_check_cluster() {
  local ctx="$1"
  if ! "$(kubectl_bin)" --context "$ctx" version --request-timeout=10s >/dev/null 2>&1; then
    log_error "cluster unreachable via context '$ctx' (try: bash platform/bootstrap.sh up)"
    return 3
  fi
  return 0
}

# Read one jsonpath field off the Deployment (empty string if absent).
_deploy_field() {
  "$(kubectl_bin)" --context "$1" --namespace "$2" get deploy "$3" -o jsonpath="$4" 2>/dev/null
}

# List crashlooping pods for a selector as "name restarts reason". A pod counts
# as crashlooping if its container is waiting in CrashLoopBackOff or its restart
# count has reached the budget.
_crashloops() {
  local ctx="$1" ns="$2" sel="$3" max="$4"
  "$(kubectl_bin)" --context "$ctx" --namespace "$ns" get pods -l "$sel" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].restartCount}{" "}{.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' 2>/dev/null |
    awk -v m="$max" '$1==""{next} $3=="CrashLoopBackOff" || ($2!="" && $2+0>=m){print $1" "$2" "$3}'
}

# One reconcile pass. Sets globals: HEAL_READY, HEAL_CRASH (count).
_heal_pass() {
  local ctx="$1" ns="$2" dep="$3" want="$4" sel="$5" max="$6" apply="$7"
  local desired ready
  desired="$(_deploy_field "$ctx" "$ns" "$dep" '{.spec.replicas}')"
  if [[ -z "$desired" ]]; then
    log_error "deployment '$dep' not found in namespace '$ns'"
    return 1
  fi

  # 1. reconcile replica drift
  if ((desired != want)); then
    echo "SCALE $dep $desired -> $want (drift from desired)"
    if ((apply)); then
      "$(kubectl_bin)" --context "$ctx" --namespace "$ns" scale deploy "$dep" "--replicas=$want" >/dev/null 2>&1 ||
        {
          log_error "scale failed for '$dep'"
          return 1
        }
    fi
  fi

  # 2. surface crashloops
  local cl line
  cl="$(_crashloops "$ctx" "$ns" "$sel" "$max")"
  HEAL_CRASH=0
  if [[ -n "$cl" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "CRASHLOOP $line"
      HEAL_CRASH=$((HEAL_CRASH + 1))
    done <<<"$cl"
  fi

  # 3. read readiness
  ready="$(_deploy_field "$ctx" "$ns" "$dep" '{.status.readyReplicas}')"
  HEAL_READY="${ready:-0}"
  return 0
}

cmd_heal() {
  local ctx="" ns="" dep="" want="" sel="" max=5 apply=0 confirm=0
  while (($#)); do
    case "$1" in
      --context)
        ctx="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --namespace)
        ns="${2:?"missing value for $1"}"
        shift
        ;;
      --deployment)
        dep="${2:?"missing value for $1"}"
        shift
        ;;
      --replicas)
        want="${2:?"missing value for $1"}"
        shift
        ;;
      --selector)
        sel="${2:?"missing value for $1"}"
        shift
        ;;
      --max-restarts)
        max="${2:?"missing value for $1"}"
        shift
        ;;
      --apply) apply=1 ;;
      --confirm) confirm=1 ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
    shift
  done
  [[ -n "$ctx" && -n "$ns" && -n "$dep" && -n "$want" ]] || usage
  is_int "$want" || {
    log_error "--replicas must be a non-negative integer: $want"
    return 1
  }
  is_int "$max" || {
    log_error "--max-restarts must be a non-negative integer: $max"
    return 1
  }
  is_valid_namespace "$ns" || {
    log_error "invalid namespace: '$ns'"
    return 2
  }
  [[ -n "$sel" ]] || sel="app=$dep"

  rm_banner "Day 29 — real self-healing (heal) against a live cluster"
  if is_protected_context "$ctx" && ((!confirm)); then
    log_error "context '$ctx' is protected; re-run with --confirm to proceed"
    return 1
  fi
  _check_cluster "$ctx" || return 3

  HEAL_READY=0 HEAL_CRASH=0
  _heal_pass "$ctx" "$ns" "$dep" "$want" "$sel" "$max" "$apply" || return 1

  echo "----------------------------"
  local mode="report"
  ((apply)) && mode="reconciled"
  printf '%s: healthy %s/%s ready, %s crashloop\n' "$mode" "$HEAL_READY" "$want" "$HEAL_CRASH"
  ((apply)) || log_info "report only — pass --apply to actually reconcile the Deployment"
  if ((HEAL_READY == want && HEAL_CRASH == 0)); then
    return 0
  fi
  return 1
}

cmd_watch() {
  local ctx="" ns="" dep="" want="" sel="" max=5 max_iter=10 interval=5 once=0 apply=0 confirm=0
  while (($#)); do
    case "$1" in
      --context)
        ctx="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --namespace)
        ns="${2:?"missing value for $1"}"
        shift
        ;;
      --deployment)
        dep="${2:?"missing value for $1"}"
        shift
        ;;
      --replicas)
        want="${2:?"missing value for $1"}"
        shift
        ;;
      --selector)
        sel="${2:?"missing value for $1"}"
        shift
        ;;
      --max-restarts)
        max="${2:?"missing value for $1"}"
        shift
        ;;
      --once) once=1 ;;
      --max-iterations)
        max_iter="${2:?"missing value for $1"}"
        shift
        ;;
      --interval)
        interval="${2:?"missing value for $1"}"
        shift
        ;;
      --apply) apply=1 ;;
      --confirm) confirm=1 ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
    shift
  done
  [[ -n "$ctx" && -n "$ns" && -n "$dep" && -n "$want" ]] || usage
  is_int "$want" || {
    log_error "--replicas must be a non-negative integer: $want"
    return 1
  }
  is_int "$max_iter" || {
    log_error "--max-iterations must be a non-negative integer: $max_iter"
    return 1
  }
  is_int "$interval" || {
    log_error "--interval must be a non-negative integer: $interval"
    return 1
  }
  ((once)) && max_iter=1

  local heal_args=(heal --context "$ctx" --namespace "$ns" --deployment "$dep" --replicas "$want" --max-restarts "$max")
  [[ -n "$sel" ]] && heal_args+=(--selector "$sel")
  ((apply)) && heal_args+=(--apply)
  ((confirm)) && heal_args+=(--confirm)

  local iter=0 rc=0
  while ((iter < max_iter)); do
    iter=$((iter + 1))
    echo "=== watchdog pass $iter/$max_iter ==="
    rc=0
    bash "$SELF" "${heal_args[@]}" || rc=$?
    if ((rc == 3)); then
      return 3
    fi
    if ((rc == 0)); then
      echo "watchdog: Deployment healthy after $iter pass(es)"
      return 0
    fi
    ((interval > 0 && iter < max_iter)) && sleep "$interval"
  done

  echo "watchdog: Deployment still degraded after $iter pass(es)"
  return 1
}

main() {
  local action="${1:-}"
  [[ -n "$action" ]] || usage
  shift
  case "$action" in
    heal) cmd_heal "$@" ;;
    watch) cmd_watch "$@" ;;
    -h | --help) usage ;;
    *)
      echo "unknown subcommand: $action" >&2
      usage
      ;;
  esac
}

main "$@"
