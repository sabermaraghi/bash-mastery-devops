#!/usr/bin/env bash
# real-chaos.sh — Option 2 (real) for Day 28: controlled chaos on a live cluster.
#
# The offline scripts (chaos-kill.sh / chaos-run.sh) practise the discipline on
# the Day 26 "cluster" (pods are files). This version injects the same faults
# into a REAL Kubernetes cluster by deleting real pods — the Deployment's
# ReplicaSet then recreates them, which is exactly the self-healing Day 29
# builds on.
#
# The three golden rules are enforced here too, against real pods:
#   1. STEADY STATE first  — count Running pods for the selector; must equal
#                            --expect before anything is injected.
#   2. BLAST RADIUS         — --max-percent (default 50) caps how many die.
#   3. REPRODUCIBLE         — --seed picks the same victims every run.
#
# It reuses the Day 25 kubectl safety rails (kubectl-lib.sh: kubectl_bin,
# current_context, is_protected_context, is_valid_namespace) and the shared
# real-mode helpers (realmode.sh). Deleting is opt-in: without --apply the
# command only previews the victims (safe by default on a real cluster).
#
# Subcommands:
#   kill  --context CTX --namespace NS --selector SEL --expect E
#         [--count N | --percent P] [--seed S] [--max-percent M]
#         [--apply] [--confirm]
#   run   --context CTX --namespace NS --selector SEL --expect E
#         [--count N] [--seed S] [--wait SECONDS] [--apply] [--confirm]
#
# `kill` injects one fault; `run` is the full experiment loop
# (steady state -> inject -> wait for natural recovery -> verify). Both talk to
# the cluster and degrade gracefully (exit 3) when kubectl or the cluster is
# absent.
#
# Exit: 0 ok/experiment passed · 1 guard or experiment failure · 2 usage
#       · 3 missing tool / cluster unreachable.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SELF="${BASH_SOURCE[0]}"
export LOG_FILE="${LOG_FILE:-/tmp/day28-real-chaos.log}" COMPONENT="real-chaos"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/days/day25/scripts/kubectl-lib.sh"

usage() {
  cat >&2 <<'EOF'
usage:
  real-chaos.sh kill --context CTX --namespace NS --selector SEL --expect E \
       [--count N | --percent P] [--seed S] [--max-percent M] [--apply] [--confirm]
  real-chaos.sh run  --context CTX --namespace NS --selector SEL --expect E \
       [--count N] [--seed S] [--wait SECONDS] [--apply] [--confirm]
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

# Running pod names for a selector, sorted. jsonpath keeps us stub-friendly.
_pods_running() {
  local ctx="$1" ns="$2" sel="$3"
  "$(kubectl_bin)" --context "$ctx" --namespace "$ns" get pods -l "$sel" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null |
    awk '$2=="Running"{print $1}' | sort
}

_count_running() { _pods_running "$1" "$2" "$3" | grep -c . || true; }

# Max pods allowed to be affected (integer floor of total*pct/100).
_blast_cap() { printf '%s' "$(($1 * $2 / 100))"; }

# Deterministic victim selection: rank by a seeded hash, take the first <count>.
# Same seed => same victims. Reads pod names on stdin. awk (not head) caps rows
# to avoid SIGPIPE under pipefail.
_pick_victims() {
  local count="$1" seed="$2" p h
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    h="$(printf '%s' "${seed}:${p}" | sha256sum | cut -c1-16)"
    printf '%s\t%s\n' "$h" "$p"
  done | sort | awk -v n="$count" 'NR<=n{print $2}'
}

cmd_kill() {
  local ctx="" ns="" sel="" expect="" count="" percent="" seed="1" max_pct=50 apply=0 confirm=0
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
      --selector)
        sel="${2:?"missing value for $1"}"
        shift
        ;;
      --expect)
        expect="${2:?"missing value for $1"}"
        shift
        ;;
      --count)
        count="${2:?"missing value for $1"}"
        shift
        ;;
      --percent)
        percent="${2:?"missing value for $1"}"
        shift
        ;;
      --seed)
        seed="${2:?"missing value for $1"}"
        shift
        ;;
      --max-percent)
        max_pct="${2:?"missing value for $1"}"
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
  [[ -n "$ctx" && -n "$ns" && -n "$sel" && -n "$expect" ]] || usage
  is_int "$expect" || {
    log_error "--expect must be a non-negative integer: $expect"
    return 1
  }
  is_valid_namespace "$ns" || {
    log_error "invalid namespace: '$ns'"
    return 2
  }

  rm_banner "Day 28 — real chaos (kill) against a live cluster"
  if is_protected_context "$ctx" && ((!confirm)); then
    log_error "context '$ctx' is protected; re-run with --confirm to proceed"
    return 1
  fi
  _check_cluster "$ctx" || return 3

  local total
  total="$(_count_running "$ctx" "$ns" "$sel")"

  # RULE 1 — steady state first.
  if ((total != expect)); then
    log_error "not in steady state: observed=$total expected=$expect — refusing to inject"
    return 1
  fi
  log_info "steady state verified: $total/$expect pods Running ($sel)"

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
    log_error "requested $requested > $total running pods"
    return 1
  }

  # RULE 2 — blast radius.
  local cap
  cap="$(_blast_cap "$total" "$max_pct")"
  if ((requested > cap)); then
    log_error "blast radius exceeded: $requested > cap $cap (${max_pct}% of $total) — raise --max-percent to override"
    return 1
  fi

  # RULE 3 — deterministic victims.
  local victims v killed=0
  victims="$(_pods_running "$ctx" "$ns" "$sel" | _pick_victims "$requested" "$seed")"
  while IFS= read -r v; do
    [[ -z "$v" ]] && continue
    echo "KILL $v"
    killed=$((killed + 1))
    ((apply)) && "$(kubectl_bin)" --context "$ctx" --namespace "$ns" delete pod "$v" --wait=false >/dev/null 2>&1
  done <<<"$victims"

  echo "----------------------------"
  local mode="preview"
  ((apply)) && mode="injected"
  printf '%s: killed %s/%s pods (blast cap %s, seed %s)\n' "$mode" "$killed" "$total" "$cap" "$seed"
  ((apply)) || log_info "preview only — pass --apply to actually delete pods"
  return 0
}

cmd_run() {
  local ctx="" ns="" sel="" expect="" count="1" seed="1" wait=60 apply=0 confirm=0
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
      --selector)
        sel="${2:?"missing value for $1"}"
        shift
        ;;
      --expect)
        expect="${2:?"missing value for $1"}"
        shift
        ;;
      --count)
        count="${2:?"missing value for $1"}"
        shift
        ;;
      --seed)
        seed="${2:?"missing value for $1"}"
        shift
        ;;
      --wait)
        wait="${2:?"missing value for $1"}"
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
  [[ -n "$ctx" && -n "$ns" && -n "$sel" && -n "$expect" ]] || usage
  is_int "$expect" || {
    log_error "--expect must be a non-negative integer: $expect"
    return 1
  }
  is_int "$wait" || {
    log_error "--wait must be a non-negative integer: $wait"
    return 1
  }
  is_valid_namespace "$ns" || {
    log_error "invalid namespace: '$ns'"
    return 2
  }

  rm_banner "Day 28 — real chaos experiment against a live cluster"
  _check_cluster "$ctx" || return 3

  local obs
  # 1. steady state (hypothesis baseline)
  obs="$(_count_running "$ctx" "$ns" "$sel")"
  echo "[1/4] steady state: observed=$obs expected=$expect"
  if ((obs != expect)); then
    echo "ABORT: not in steady state before experiment"
    log_error "experiment aborted — baseline not steady ($obs/$expect)"
    return 1
  fi

  # 2. inject (re-use the guarded kill path)
  echo "[2/4] injecting fault (count=$count seed=$seed)"
  local kill_args=(kill --context "$ctx" --namespace "$ns" --selector "$sel" --expect "$expect" --count "$count" --seed "$seed")
  ((apply)) && kill_args+=(--apply)
  ((confirm)) && kill_args+=(--confirm)
  bash "$SELF" "${kill_args[@]}" || {
    log_error "fault injection failed"
    return 1
  }

  if ((!apply)); then
    echo "[preview] no --apply given — skipping wait/verify"
    return 0
  fi

  # 3. wait for natural recovery (the ReplicaSet recreates deleted pods)
  echo "[3/4] waiting up to ${wait}s for the cluster to self-heal"
  local waited=0
  while ((waited < wait)); do
    obs="$(_count_running "$ctx" "$ns" "$sel")"
    ((obs == expect)) && break
    sleep 3
    waited=$((waited + 3))
  done

  # 4. verify
  obs="$(_count_running "$ctx" "$ns" "$sel")"
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

main() {
  local action="${1:-}"
  [[ -n "$action" ]] || usage
  shift
  case "$action" in
    kill) cmd_kill "$@" ;;
    run) cmd_run "$@" ;;
    -h | --help) usage ;;
    *)
      echo "unknown subcommand: $action" >&2
      usage
      ;;
  esac
}

main "$@"
