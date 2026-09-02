#!/usr/bin/env bash
# k-apply.sh — a safe wrapper around `kubectl apply`.
#
# Safety rails:
#   - --context and --namespace are REQUIRED (no implicit "current" target)
#   - dry-run by default (server-side); real changes need --apply
#   - protected (prod-like) contexts are refused unless --confirm is given
#   - the manifest path must exist; the namespace name is validated
#
# Usage:
#   bash k-apply.sh --context CTX --namespace NS [--apply] [--confirm] MANIFEST
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day25-apply.log}" COMPONENT="k-apply"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/kubectl-lib.sh"

usage() {
  echo "usage: $0 --context CTX --namespace NS [--apply] [--confirm] MANIFEST" >&2
  exit 2
}

main() {
  local context="" namespace="" do_apply=0 confirm=0 manifest=""
  while (($#)); do
    case "$1" in
      --context)
        context="${2:?}"
        shift
        ;;
      --namespace)
        namespace="${2:?}"
        shift
        ;;
      --apply) do_apply=1 ;;
      --confirm) confirm=1 ;;
      -h | --help) usage ;;
      -*)
        echo "unknown flag: $1" >&2
        usage
        ;;
      *) [[ -z "$manifest" ]] && manifest="$1" || usage ;;
    esac
    shift
  done

  [[ -n "$context" && -n "$namespace" && -n "$manifest" ]] || usage
  is_valid_namespace "$namespace" || {
    log_error "invalid namespace: $namespace"
    return 1
  }
  [[ -e "$manifest" ]] || {
    log_error "manifest not found: $manifest"
    return 1
  }

  if is_protected_context "$context" && ((confirm == 0)); then
    log_error "refusing to target protected context '$context' without --confirm"
    return 1
  fi

  local -a cmd=("$(kubectl_bin)" --context "$context" --namespace "$namespace" apply -f "$manifest")
  if ((do_apply == 0)); then
    cmd+=(--dry-run=server)
    log_info "DRY-RUN (server) apply to $context/$namespace — pass --apply to make it real"
  else
    log_warn "LIVE apply to $context/$namespace"
  fi

  "${cmd[@]}"
}

main "$@"
