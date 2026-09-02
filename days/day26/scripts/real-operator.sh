#!/usr/bin/env bash
# real-operator.sh — Option 2 (real) for Day 26.
#
# The offline operator (operator.sh / reconcile-cr.sh) simulates "pods" as files.
# This version runs the SAME reconcile pattern against a real Kubernetes cluster:
# it reads a WidgetSet CustomResource and converges the cluster toward it by
# managing a Deployment — which is Kubernetes' own built-in reconciler. That's
# the honest real analog: an operator composes existing controllers.
#
# It reuses the offline CR parser (operator-lib.sh: cr_get / is_uint) and the
# Day 25 kubectl safety rails (kubectl-lib.sh: kubectl_bin, current_context,
# is_protected_context, is_valid_namespace) — same guarantees, real target.
#
# Subcommands:
#   reconcile --cr FILE --context CTX --namespace NS [--apply] [--confirm]
#   status    --cr FILE --context CTX --namespace NS
#   watch     --cr-dir DIR --context CTX --namespace NS [--once]
#             [--interval N] [--max-iterations N] [--apply] [--confirm]
#   delete    --cr FILE --context CTX --namespace NS [--confirm]
#
# Exit: 0 ok · 1 apply/guard failure · 2 usage · 3 missing tool / unreachable.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day26-real-operator.log}" COMPONENT="real-operator"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/operator-lib.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/days/day25/scripts/kubectl-lib.sh"

MANAGED_BY="day26-operator"

usage() {
  cat >&2 <<'EOF'
usage:
  real-operator.sh reconcile --cr FILE --context CTX --namespace NS [--apply] [--confirm]
  real-operator.sh status    --cr FILE --context CTX --namespace NS
  real-operator.sh watch     --cr-dir DIR --context CTX --namespace NS [--once] [--interval N] [--max-iterations N] [--apply] [--confirm]
  real-operator.sh delete    --cr FILE --context CTX --namespace NS [--confirm]
EOF
  exit 2
}

# Prove the target cluster is reachable, else exit 3 (never fake a change).
_check_cluster() {
  local ctx="$1"
  if ! "$(kubectl_bin)" --context "$ctx" version --request-timeout=10s >/dev/null 2>&1; then
    log_error "cluster unreachable via context '$ctx' (is it up? try: bash platform/bootstrap.sh up)"
    return 3
  fi
  return 0
}

# Read + validate a WidgetSet CR into the globals CR_NAME/CR_REPLICAS/CR_IMAGE.
_read_cr() {
  local cr="$1" kind
  [[ -f "$cr" ]] || {
    log_error "CR file not found: $cr"
    return 2
  }
  kind="$(cr_get "$cr" kind || true)"
  CR_NAME="$(cr_get "$cr" name || true)"
  CR_REPLICAS="$(cr_get "$cr" replicas || true)"
  CR_IMAGE="$(cr_get "$cr" image || true)"
  [[ "$kind" == "WidgetSet" ]] || {
    log_error "unsupported kind: '${kind:-<none>}' (want WidgetSet)"
    return 2
  }
  [[ -n "$CR_NAME" && -n "$CR_IMAGE" ]] || {
    log_error "CR missing name or image"
    return 2
  }
  is_uint "$CR_REPLICAS" || {
    log_error "replicas must be a non-negative integer, got '${CR_REPLICAS:-<none>}'"
    return 2
  }
  return 0
}

# Emit the Deployment manifest that represents the desired WidgetSet state.
_manifest() {
  local name="$1" replicas="$2" image="$3"
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
  labels:
    app.kubernetes.io/name: ${name}
    app.kubernetes.io/managed-by: ${MANAGED_BY}
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app.kubernetes.io/name: ${name}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${name}
        app.kubernetes.io/managed-by: ${MANAGED_BY}
    spec:
      containers:
        - name: ${name}
          image: ${image}
EOF
}

# Shared guard: validate namespace, check protected context + confirm.
_guard_target() {
  local ctx="$1" ns="$2" confirm="$3" needs_confirm="${4:-1}"
  is_valid_namespace "$ns" || {
    log_error "invalid namespace: '$ns'"
    return 2
  }
  if ((needs_confirm)) && is_protected_context "$ctx" && ((!confirm)); then
    log_error "context '$ctx' is protected; re-run with --confirm to proceed"
    return 1
  fi
  return 0
}

cmd_reconcile() {
  local cr="" ctx="" ns="" apply=0 confirm=0
  while (($#)); do
    case "$1" in
      --cr)
        cr="${2:?}"
        shift
        ;;
      --context)
        ctx="${2:?}"
        shift
        ;;
      --namespace)
        ns="${2:?}"
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
  [[ -n "$cr" && -n "$ctx" && -n "$ns" ]] || usage
  _read_cr "$cr" || return $?
  _guard_target "$ctx" "$ns" "$confirm" 1 || return $?
  _check_cluster "$ctx" || return 3

  local -a k=("$(kubectl_bin)" --context "$ctx" --namespace "$ns" apply -f -)
  if ((apply)); then
    log_info "reconciling WidgetSet/$CR_NAME -> Deployment (replicas=$CR_REPLICAS image=$CR_IMAGE)"
  else
    k+=(--dry-run=server)
    log_info "preview (server dry-run) WidgetSet/$CR_NAME -> Deployment; pass --apply to converge"
  fi

  if _manifest "$CR_NAME" "$CR_REPLICAS" "$CR_IMAGE" | "${k[@]}"; then
    return 0
  fi
  log_error "reconcile failed for WidgetSet/$CR_NAME"
  return 1
}

cmd_status() {
  local cr="" ctx="" ns=""
  while (($#)); do
    case "$1" in
      --cr)
        cr="${2:?}"
        shift
        ;;
      --context)
        ctx="${2:?}"
        shift
        ;;
      --namespace)
        ns="${2:?}"
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
  [[ -n "$cr" && -n "$ctx" && -n "$ns" ]] || usage
  _read_cr "$cr" || return $?
  is_valid_namespace "$ns" || {
    log_error "invalid namespace: '$ns'"
    return 2
  }
  _check_cluster "$ctx" || return 3

  # Read observed state back from the cluster (the real "status subresource").
  local desired ready
  desired="$("$(kubectl_bin)" --context "$ctx" --namespace "$ns" get deployment "$CR_NAME" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
  if [[ -z "$desired" ]]; then
    log_warn "WidgetSet/$CR_NAME has no Deployment yet in $ns (run reconcile --apply)"
    return 0
  fi
  ready="$("$(kubectl_bin)" --context "$ctx" --namespace "$ns" get deployment "$CR_NAME" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  ready="${ready:-0}"
  local phase="Ready"
  [[ "$ready" == "$desired" ]] || phase="Scaling"
  printf 'WidgetSet/%s  phase=%s  ready=%s/%s  image=%s\n' \
    "$CR_NAME" "$phase" "$ready" "$desired" "$CR_IMAGE"
  return 0
}

cmd_delete() {
  local cr="" ctx="" ns="" confirm=0
  while (($#)); do
    case "$1" in
      --cr)
        cr="${2:?}"
        shift
        ;;
      --context)
        ctx="${2:?}"
        shift
        ;;
      --namespace)
        ns="${2:?}"
        shift
        ;;
      --confirm) confirm=1 ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
    shift
  done
  [[ -n "$cr" && -n "$ctx" && -n "$ns" ]] || usage
  _read_cr "$cr" || return $?
  _guard_target "$ctx" "$ns" "$confirm" 1 || return $?
  _check_cluster "$ctx" || return 3

  log_info "deleting Deployment for WidgetSet/$CR_NAME in $ns"
  if "$(kubectl_bin)" --context "$ctx" --namespace "$ns" delete deployment "$CR_NAME" --ignore-not-found; then
    return 0
  fi
  log_error "delete failed for WidgetSet/$CR_NAME"
  return 1
}

cmd_watch() {
  local cr_dir="" ctx="" ns="" once=0 interval=5 max=0 apply=0 confirm=0
  while (($#)); do
    case "$1" in
      --cr-dir)
        cr_dir="${2:?}"
        shift
        ;;
      --context)
        ctx="${2:?}"
        shift
        ;;
      --namespace)
        ns="${2:?}"
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
  [[ -n "$cr_dir" && -n "$ctx" && -n "$ns" ]] || usage
  [[ -d "$cr_dir" ]] || {
    log_error "cr-dir not found: $cr_dir"
    return 2
  }

  local iter=0 cr found rc=0
  local -a fwd=(--context "$ctx" --namespace "$ns")
  ((apply)) && fwd+=(--apply)
  ((confirm)) && fwd+=(--confirm)
  while true; do
    iter=$((iter + 1))
    found=0
    shopt -s nullglob
    for cr in "$cr_dir"/*.cr; do
      found=1
      log_info "reconciling $(basename "$cr") (iteration $iter)"
      cmd_reconcile --cr "$cr" "${fwd[@]}" || rc=$?
    done
    shopt -u nullglob
    ((found)) || log_warn "no *.cr manifests found in $cr_dir"
    ((once)) && break
    ((max > 0 && iter >= max)) && break
    sleep "$interval"
  done
  return "$rc"
}

main() {
  local action="${1:-}"
  [[ -n "$action" ]] || usage
  shift
  case "$action" in
    reconcile | status | watch | delete) ;;
    -h | --help) usage ;;
    *)
      echo "unknown subcommand: $action" >&2
      usage
      ;;
  esac

  rm_require_tools "$(kubectl_bin)" || return 3
  [[ "$action" == "status" ]] || rm_banner "Day 26 — operator reconcile ($action) against a live cluster" >&2

  case "$action" in
    reconcile) cmd_reconcile "$@" ;;
    status) cmd_status "$@" ;;
    watch) cmd_watch "$@" ;;
    delete) cmd_delete "$@" ;;
  esac
}

main "$@"
