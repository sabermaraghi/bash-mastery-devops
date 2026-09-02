#!/usr/bin/env bash
# real-kubectl.sh — Day 25, Option 2 (REAL): safe kubectl automation against a
# real cluster.
#
# The offline default (k-apply.sh + context-guard.sh + kubectl-lib.sh) proves
# the *safety rails* with a stub kubectl: explicit targeting, dry-run first, a
# protected-context guard, and a current-context assertion. This runs those very
# same rails against an ACTUAL cluster — it reuses the offline helpers
# (is_protected_context / is_valid_namespace / current_context) so the guarantees
# are identical; only the target changes from a stub to a live API server.
#
# Subcommands:
#   apply  — safe `kubectl apply` (dry-run=server by default; --apply to mutate;
#            protected contexts refused without --confirm; explicit targeting)
#   guard  — assert the live current-context equals EXPECTED before risky work
#   get    — read-only inspection of live objects (never mutates)
#
# Usage:
#   bash real-kubectl.sh apply --context CTX --namespace NS [--apply] [--confirm] MANIFEST
#   bash real-kubectl.sh guard EXPECTED_CONTEXT
#   bash real-kubectl.sh get   --context CTX --namespace NS [RESOURCE...]
#
# The client binary is resolved via $KUBECTL (default kubectl), so this works
# with `oc`, a pinned `kubectl-1.30`, etc. Protected contexts come from
# $PROTECTED_CONTEXTS (comma-separated; default "prod,production").
#
# Requires kubectl. A missing tool or an unreachable cluster is a clear message
# and exit 3 — it never fakes a change.
# Exit: 0 ok · 1 guard mismatch / apply failure · 2 usage · 3 missing tool/cluster.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day25-real-kubectl.log}" COMPONENT="real-kubectl"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"
# Compose the offline safety helpers so REAL mode enforces the SAME rules.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/kubectl-lib.sh"

usage() {
  {
    echo "usage: $0 apply --context CTX --namespace NS [--apply] [--confirm] MANIFEST"
    echo "       $0 guard EXPECTED_CONTEXT"
    echo "       $0 get   --context CTX --namespace NS [RESOURCE...]"
  } >&2
  return 2
}

# Confirm the cluster is actually reachable before we claim to touch it.
#   $1 = context (may be empty to use the current one)
_check_cluster() {
  local ctx="${1:-}" scope=()
  [[ -n "$ctx" ]] && scope=(--context "$ctx")
  if ! "$(kubectl_bin)" "${scope[@]}" version --request-timeout=10s >/dev/null 2>&1; then
    log_error "cluster unreachable (check --context / kubeconfig / that the cluster is up)"
    return 3
  fi
  return 0
}

cmd_apply() {
  local context="" namespace="" do_apply=0 confirm=0 manifest=""
  while (($#)); do
    case "$1" in
      --context)
        context="${2:?--context needs a value}"
        shift 2
        ;;
      --namespace)
        namespace="${2:?--namespace needs a value}"
        shift 2
        ;;
      --apply)
        do_apply=1
        shift
        ;;
      --confirm)
        confirm=1
        shift
        ;;
      -h | --help) usage ;;
      -*)
        echo "unknown flag: $1" >&2
        usage
        ;;
      *)
        [[ -z "$manifest" ]] && manifest="$1" || usage
        shift
        ;;
    esac
  done

  # Explicit targeting is mandatory — never trust the ambient context.
  [[ -n "$context" && -n "$namespace" && -n "$manifest" ]] || usage
  is_valid_namespace "$namespace" || {
    log_error "invalid namespace: $namespace"
    return 2
  }
  [[ -e "$manifest" ]] || {
    log_error "manifest not found: $manifest"
    return 2
  }
  if is_protected_context "$context" && ((confirm == 0)); then
    log_error "refusing to target protected context '$context' without --confirm"
    return 1
  fi

  _check_cluster "$context" || return 3

  local -a cmd=("$(kubectl_bin)" --context "$context" --namespace "$namespace" apply -f "$manifest")
  if ((do_apply == 0)); then
    cmd+=(--dry-run=server)
    log_info "DRY-RUN (server) apply to $context/$namespace — pass --apply to make it real"
  else
    log_warn "LIVE apply to $context/$namespace"
  fi

  if "${cmd[@]}"; then
    ((do_apply)) && log_info "apply complete: $context/$namespace now matches $manifest" ||
      log_info "dry-run complete (nothing changed)"
    return 0
  fi
  log_error "kubectl apply failed"
  return 1
}

cmd_guard() {
  local expected="${1:-}"
  [[ -n "$expected" ]] || {
    echo "guard: EXPECTED_CONTEXT required" >&2
    usage
  }
  local current
  current="$(current_context)" || true
  if [[ -z "$current" ]]; then
    log_error "could not determine current context (is a cluster configured?)"
    return 3
  fi
  if [[ "$current" == "$expected" ]]; then
    echo "context OK: $current"
    return 0
  fi
  echo "context MISMATCH: current='$current' expected='$expected'" >&2
  log_error "context guard blocked: current=$current expected=$expected"
  return 1
}

cmd_get() {
  local context="" namespace=""
  local -a resources=()
  while (($#)); do
    case "$1" in
      --context)
        context="${2:?--context needs a value}"
        shift 2
        ;;
      --namespace)
        namespace="${2:?--namespace needs a value}"
        shift 2
        ;;
      -h | --help) usage ;;
      -*)
        echo "unknown flag: $1" >&2
        usage
        ;;
      *)
        resources+=("$1")
        shift
        ;;
    esac
  done
  [[ -n "$context" && -n "$namespace" ]] || usage
  is_valid_namespace "$namespace" || {
    log_error "invalid namespace: $namespace"
    return 2
  }
  # Read-only default: pods. Never mutates regardless of arguments.
  ((${#resources[@]})) || resources=(pods)
  _check_cluster "$context" || return 3
  log_info "get ${resources[*]} in $context/$namespace (read-only)"
  "$(kubectl_bin)" --context "$context" --namespace "$namespace" get "${resources[@]}"
}

main() {
  local action="${1:-}"
  case "$action" in
    apply | guard | get) shift ;;
    -h | --help)
      usage
      return 2
      ;;
    "")
      echo "missing subcommand" >&2
      usage
      return 2
      ;;
    *)
      echo "unknown subcommand: $action" >&2
      usage
      return 2
      ;;
  esac

  rm_require_tools "$(kubectl_bin)" || return 3
  rm_banner "Day 25 — safe kubectl automation ($action against a live cluster)"

  case "$action" in
    apply) cmd_apply "$@" ;;
    guard) cmd_guard "$@" ;;
    get) cmd_get "$@" ;;
  esac
}

main "$@"
