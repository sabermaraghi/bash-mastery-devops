#!/usr/bin/env bash
# real-cost.sh — Option 2 (real) for Day 30: cost & FinOps on a live cluster.
#
# The offline scripts price *.workload files. On a real cluster the same two
# numbers come straight from Kubernetes:
#   - what you RESERVE (and pay for) = Deployment resource *requests*
#     (kubectl get deploy ... .spec.template.spec.containers[0].resources.requests)
#   - what you actually USE          = live metrics (kubectl top pods)
# The gap between them is waste — exactly what FinOps hunts. This reuses the
# offline cost math (cost-lib.sh) so the numbers match the lesson.
#
# Subcommands:
#   report    --context CTX --namespace NS [--selector SEL]
#             [--cpu-price P] [--mem-price P] [--hours H]
#   rightsize --context CTX --namespace NS [--selector SEL]
#             [--low 30] [--high 90] [--target 60]
#             [--cpu-price P] [--mem-price P] [--hours H]
#
# `report` prices every Deployment's requests (read-only). `rightsize` compares
# requests against live usage from metrics-server and flags WASTE/RISK, exiting
# non-zero if the fleet needs attention — a FinOps CI gate.
#
# Both are READ-ONLY (no --apply): they never mutate the cluster. They degrade
# gracefully with exit 3 when kubectl, the cluster, or metrics-server is absent.
#
# Exit: 0 clean · 1 workloads need right-sizing · 2 usage
#       · 3 missing tool / cluster unreachable / no metrics.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day30-real-cost.log}" COMPONENT="real-cost"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/days/day25/scripts/kubectl-lib.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/cost-lib.sh"

usage() {
  cat >&2 <<'EOF'
usage:
  real-cost.sh report    --context CTX --namespace NS [--selector SEL] \
       [--cpu-price P] [--mem-price P] [--hours H]
  real-cost.sh rightsize --context CTX --namespace NS [--selector SEL] \
       [--low 30] [--high 90] [--target 60] [--cpu-price P] [--mem-price P] [--hours H]
EOF
  exit 2
}

# Normalise a Kubernetes CPU quantity to millicores. '' -> 0, '500m' -> 500,
# '2' -> 2000.
_norm_cpu() {
  awk -v v="${1:-}" 'BEGIN {
    if (v == "") { print 0; exit }
    if (v ~ /m$/) { sub(/m$/, "", v); printf "%d", v + 0 }
    else { printf "%d", (v + 0) * 1000 }
  }'
}

# Normalise a Kubernetes memory quantity to MiB. Handles Ki/Mi/Gi/Ti suffixes,
# decimal K/M/G, and plain bytes.
_norm_mem() {
  awk -v v="${1:-}" 'BEGIN {
    if (v == "") { print 0; exit }
    n = v; sub(/[A-Za-z]+$/, "", n); n = n + 0
    if (v ~ /Ki$/) { printf "%d", n / 1024 }
    else if (v ~ /Mi$/) { printf "%d", n }
    else if (v ~ /Gi$/) { printf "%d", n * 1024 }
    else if (v ~ /Ti$/) { printf "%d", n * 1024 * 1024 }
    else if (v ~ /K$/) { printf "%d", n * 1000 / 1048576 }
    else if (v ~ /M$/) { printf "%d", n * 1000000 / 1048576 }
    else if (v ~ /G$/) { printf "%d", n * 1000000000 / 1048576 }
    else { printf "%d", n / 1048576 }
  }'
}

_check_cluster() {
  local ctx="$1"
  if ! "$(kubectl_bin)" --context "$ctx" version --request-timeout=10s >/dev/null 2>&1; then
    log_error "cluster unreachable via context '$ctx' (try: bash platform/bootstrap.sh up)"
    return 3
  fi
  return 0
}

# Emit "name replicas cpuRequest memRequest" per Deployment (raw K8s quantities).
_deploy_rows() {
  local ctx="$1" ns="$2" sel="$3" args=()
  [[ -n "$sel" ]] && args=(-l "$sel")
  "$(kubectl_bin)" --context "$ctx" --namespace "$ns" get deploy "${args[@]}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.replicas}{" "}{.spec.template.spec.containers[0].resources.requests.cpu}{" "}{.spec.template.spec.containers[0].resources.requests.memory}{"\n"}{end}' 2>/dev/null
}

# Average live usage per replica for a workload, as "cpuMillicores memMiB".
# Uses `kubectl top pods`; returns non-zero if metrics are unavailable.
_avg_usage() {
  local ctx="$1" ns="$2" sel="$3" out
  out="$("$(kubectl_bin)" --context "$ctx" --namespace "$ns" top pods -l "$sel" --no-headers 2>/dev/null)" || return 1
  [[ -n "$out" ]] || {
    printf '0 0'
    return 0
  }
  printf '%s\n' "$out" | awk '
    function ncpu(v) { if (v ~ /m$/) { sub(/m$/, "", v); return v + 0 } return (v + 0) * 1000 }
    function nmem(v,  n) { n = v; sub(/[A-Za-z]+$/, "", n); n = n + 0;
      if (v ~ /Gi$/) return n * 1024; if (v ~ /Ki$/) return n / 1024; if (v ~ /Mi$/) return n; return n / 1048576 }
    { c += ncpu($2); m += nmem($3); k++ }
    END { if (k == 0) { print "0 0" } else { printf "%d %d", c / k, m / k } }'
}

common_parse() {
  CTX=""
  NS=""
  SEL=""
  CPU_PRICE="0.031"
  MEM_PRICE="0.004"
  HOURS="730"
  LOW=30
  HIGH=90
  TARGET=60
  while (($#)); do
    case "$1" in
      --context)
        CTX="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --namespace)
        NS="${2:?"missing value for $1"}"
        shift
        ;;
      --selector)
        SEL="${2:?"missing value for $1"}"
        shift
        ;;
      --cpu-price)
        CPU_PRICE="${2:?"missing value for $1"}"
        shift
        ;;
      --mem-price)
        MEM_PRICE="${2:?"missing value for $1"}"
        shift
        ;;
      --hours)
        HOURS="${2:?"missing value for $1"}"
        shift
        ;;
      --low)
        LOW="${2:?"missing value for $1"}"
        shift
        ;;
      --high)
        HIGH="${2:?"missing value for $1"}"
        shift
        ;;
      --target)
        TARGET="${2:?"missing value for $1"}"
        shift
        ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
    shift
  done
  [[ -n "$CTX" && -n "$NS" ]] || usage
  is_valid_namespace "$NS" || {
    log_error "invalid namespace: '$NS'"
    return 2
  }
  return 0
}

cmd_report() {
  common_parse "$@" || return $?
  rm_banner "Day 30 — real cost report (live cluster requests)"
  _check_cluster "$CTX" || return 3

  local rows
  rows="$(_deploy_rows "$CTX" "$NS" "$SEL")"
  [[ -n "$rows" ]] || {
    log_error "no Deployments found in namespace '$NS'"
    return 1
  }

  printf '%-16s %8s %8s %8s %12s\n' "WORKLOAD" "REPLICAS" "CPU(m)" "MEM(Mi)" "COST/MO($)"
  printf '%-16s %8s %8s %8s %12s\n' "----------------" "--------" "------" "-------" "------------"

  local name rep cpu mem cpum memmi cost costs=""
  while read -r name rep cpu mem; do
    [[ -z "$name" ]] && continue
    [[ -z "$rep" || "$rep" == "<none>" ]] && rep=1
    cpum="$(_norm_cpu "$cpu")"
    memmi="$(_norm_mem "$mem")"
    cost="$(workload_cost "$rep" "$cpum" "$memmi" "$CPU_PRICE" "$MEM_PRICE" "$HOURS")"
    costs+="$cost"$'\n'
    printf '%-16s %8s %8s %8s %12s\n' "$name" "$rep" "$cpum" "$memmi" "$cost"
  done <<<"$rows"

  local total
  total="$(printf '%s' "$costs" | awk '{ s += $1 } END { printf "%.2f", s }')"
  printf '%-16s %8s %8s %8s %12s\n' "----------------" "--------" "------" "-------" "------------"
  printf '%-16s %8s %8s %8s %12s\n' "TOTAL" "" "" "" "$total"
}

cmd_rightsize() {
  common_parse "$@" || return $?
  rm_banner "Day 30 — real right-sizing (requests vs live usage)"
  _check_cluster "$CTX" || return 3

  local rows
  rows="$(_deploy_rows "$CTX" "$NS" "$SEL")"
  [[ -n "$rows" ]] || {
    log_error "no Deployments found in namespace '$NS'"
    return 1
  }

  # Verify metrics-server is available before we start.
  if ! "$(kubectl_bin)" --context "$CTX" --namespace "$NS" top pods --no-headers >/dev/null 2>&1; then
    log_error "metrics unavailable (kubectl top failed) — install metrics-server to right-size"
    return 3
  fi

  printf '%-14s %-6s %9s %9s %10s %10s %10s\n' \
    "WORKLOAD" "STATUS" "CPU%" "MEM%" "REC_CPU" "REC_MEM" "SAVE/MO$"
  printf '%-14s %-6s %9s %9s %10s %10s %10s\n' \
    "--------------" "------" "--------" "--------" "---------" "---------" "---------"

  local name rep cpu mem cpum memmi wsel usage cuse muse line
  local savings="" flagged=0
  while read -r name rep cpu mem; do
    [[ -z "$name" ]] && continue
    [[ -z "$rep" || "$rep" == "<none>" ]] && rep=1
    cpum="$(_norm_cpu "$cpu")"
    memmi="$(_norm_mem "$mem")"
    wsel="${SEL:-app=$name}"
    usage="$(_avg_usage "$CTX" "$NS" "$wsel")"
    cuse="${usage%% *}"
    muse="${usage##* }"

    line="$(awk -v r="$rep" -v cr="$cpum" -v mr="$memmi" -v cu="$cuse" -v mu="$muse" \
      -v low="$LOW" -v high="$HIGH" -v tgt="$TARGET" -v cp="$CPU_PRICE" -v mp="$MEM_PRICE" -v h="$HOURS" 'BEGIN {
        cutil = (cr > 0) ? cu / cr * 100 : 0
        mutil = (mr > 0) ? mu / mr * 100 : 0
        status = "OK"
        if (cutil >= high || mutil >= high) status = "RISK"
        else if (cutil < low || mutil < low) status = "WASTE"
        reccr = cr; recmr = mr
        if (status != "OK") {
          reccr = ceil(cu / (tgt / 100)); recmr = ceil(mu / (tgt / 100))
          if (reccr < 1) reccr = 1
          if (recmr < 1) recmr = 1
        }
        cur = r * ((cr / 1000) * cp + (mr / 1024) * mp) * h
        rec = r * ((reccr / 1000) * cp + (recmr / 1024) * mp) * h
        printf "%s\t%.0f\t%.0f\t%d\t%d\t%.2f", status, cutil, mutil, reccr, recmr, cur - rec
      }
      function ceil(x) { return (x == int(x)) ? x : int(x) + 1 }')"

    local status cutil mutil reccr recmr save
    IFS=$'\t' read -r status cutil mutil reccr recmr save <<<"$line"
    [[ "$status" == "OK" ]] || flagged=1
    savings+="$save"$'\n'
    printf '%-14s %-6s %8s%% %8s%% %10s %10s %10s\n' \
      "$name" "$status" "$cutil" "$mutil" "$reccr" "$recmr" "$save"
  done <<<"$rows"

  local net
  net="$(printf '%s' "$savings" | awk '{ s += $1 } END { printf "%.2f", s }')"
  printf '%-14s %-6s %9s %9s %10s %10s %10s\n' \
    "--------------" "------" "--------" "--------" "---------" "---------" "---------"
  printf 'Potential monthly savings: $%s\n' "$net"
  if ((flagged)); then
    echo "RESULT: workloads need right-sizing"
    return 1
  fi
  echo "RESULT: all workloads right-sized"
}

main() {
  local action="${1:-}"
  [[ -n "$action" ]] || usage
  shift
  case "$action" in
    report) cmd_report "$@" ;;
    rightsize) cmd_rightsize "$@" ;;
    -h | --help) usage ;;
    *)
      echo "unknown subcommand: $action" >&2
      usage
      ;;
  esac
}

main "$@"
