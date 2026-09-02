#!/usr/bin/env bash
# real-gitops.sh — Day 24, Option 2 (REAL): GitOps against a real cluster.
#
# The offline default (reconcile.sh + drift-detect.sh) models GitOps by syncing
# one directory into another and comparing SHA-256 hashes. This runs the same
# loop for real: the DESIRED state is a directory of Kubernetes manifests (your
# git source of truth) and the LIVE state is an actual cluster namespace.
#
#   • reconcile  — make the cluster match the manifests   (kubectl apply)
#   • drift      — read-only; non-zero when reality diverged (kubectl diff)
#
# Optionally pulls the desired state straight from a git remote first (the
# GitOps "pull" model), so the flow is: git -> manifests -> cluster.
#
# Usage:
#   bash real-gitops.sh reconcile --dir DIR [--namespace NS] [--context CTX] \
#                                 [--dry-run] [--prune]
#   bash real-gitops.sh drift     --dir DIR [--namespace NS] [--context CTX]
#
#   Common flags:
#     --dir DIR        directory of manifests to apply/compare (required unless --git-url)
#     --namespace NS   target namespace (default: current context's namespace)
#     --context CTX    kube-context to use (default: current context)
#     --git-url URL    clone this git repo and use --path inside it as --dir
#     --git-ref REF    branch/tag/sha to check out (default: default branch)
#     --path SUBDIR    subdirectory inside the cloned repo (default: repo root)
#   reconcile-only:
#     --dry-run        server-side dry run: plan the apply, change nothing
#     --prune          delete cluster objects no longer declared (label-scoped)
#     --label SELECTOR prune label selector (default: app.kubernetes.io/managed-by=day24-gitops)
#
# Requires kubectl (and git when --git-url is used). A missing tool or an
# unreachable cluster is a clear message and exit 3 — it never fakes a sync.
# Exit: 0 in-sync/applied · 1 drift detected · 2 usage · 3 missing tool/cluster.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day24-real-gitops.log}" COMPONENT="real-gitops"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"

PRUNE_DEFAULT_LABEL="app.kubernetes.io/managed-by=day24-gitops"
_CLONE_DIR=""

# Clean up any temporary git clone on exit.
_cleanup() {
  if [[ -n "$_CLONE_DIR" && -d "$_CLONE_DIR" ]]; then
    rm -rf "$_CLONE_DIR"
  fi
  return 0
}
trap _cleanup EXIT

usage() {
  echo "usage: $0 {reconcile|drift} --dir DIR [--namespace NS] [--context CTX]" >&2
  echo "       [--git-url URL [--git-ref REF] [--path SUBDIR]]" >&2
  echo "       reconcile-only: [--dry-run] [--prune] [--label SELECTOR]" >&2
  return 2
}

# Build the shared "where" flags (context + namespace) into a global array.
_kube_scope=()
_build_scope() {
  _kube_scope=()
  [[ -n "${1:-}" ]] && _kube_scope+=(--context "$1")
  [[ -n "${2:-}" ]] && _kube_scope+=(--namespace "$2")
  return 0
}

# Fetch the desired manifests from a git remote into a temp dir; echo the path.
_git_fetch() {
  local url="$1" ref="$2" sub="$3"
  rm_require_tools git || return 3
  _CLONE_DIR="$(mktemp -d)"
  log_info "cloning $url (ref: ${ref:-default}) -> $_CLONE_DIR"
  if ! git clone --depth 1 ${ref:+--branch "$ref"} "$url" "$_CLONE_DIR" >&2; then
    log_error "git clone failed: $url"
    return 3
  fi
  local dir="$_CLONE_DIR"
  [[ -n "$sub" ]] && dir="$_CLONE_DIR/$sub"
  [[ -d "$dir" ]] || {
    log_error "path not found in repo: ${sub:-/}"
    return 2
  }
  printf '%s\n' "$dir"
}

# Confirm the cluster is actually reachable before we claim to sync it.
_check_cluster() {
  if ! kubectl "${_kube_scope[@]}" version --request-timeout=10s >/dev/null 2>&1; then
    log_error "cluster unreachable (check --context / kubeconfig / that the cluster is up)"
    return 3
  fi
  return 0
}

cmd_reconcile() {
  local dir="$1" ctx="$2" ns="$3" dry="$4" prune="$5" label="$6"
  _build_scope "$ctx" "$ns"
  _check_cluster || return 3

  local apply=(kubectl "${_kube_scope[@]}" apply -f "$dir")
  ((dry)) && apply+=(--dry-run=server)
  if ((prune)); then
    apply+=(--prune -l "$label")
  fi

  local mode="apply"
  ((dry)) && mode="plan (server dry-run)"
  log_info "reconcile: $mode  dir=$dir  ns=${ns:-<current>}  prune=$prune"
  if "${apply[@]}"; then
    if ((dry)); then
      log_info "reconcile plan complete (nothing changed)"
    else
      log_info "reconcile applied: cluster now matches $dir"
    fi
    return 0
  fi
  log_error "reconcile failed (kubectl apply returned non-zero)"
  return 1
}

cmd_drift() {
  local dir="$1" ctx="$2" ns="$3"
  _build_scope "$ctx" "$ns"
  _check_cluster || return 3

  # kubectl diff: exit 0 = no diff, 1 = diff present, >1 = real error.
  log_info "drift: comparing $dir against live cluster"
  local rc=0
  kubectl "${_kube_scope[@]}" diff -f "$dir" || rc=$?
  case "$rc" in
    0)
      echo "no drift: LIVE matches DESIRED"
      log_info "no drift"
      return 0
      ;;
    1)
      echo "----------------------------"
      echo "drift detected: cluster diverged from $dir"
      log_error "drift detected"
      return 1
      ;;
    *)
      log_error "kubectl diff errored (rc=$rc)"
      return 3
      ;;
  esac
}

main() {
  local action="${1:-}"
  case "$action" in
    reconcile | drift) shift ;;
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

  local dir="" ns="" ctx="" dry=0 prune=0 label="$PRUNE_DEFAULT_LABEL"
  local git_url="" git_ref="" git_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        dir="${2:?--dir needs a path}"
        shift 2
        ;;
      --namespace)
        ns="${2:?--namespace needs a value}"
        shift 2
        ;;
      --context)
        ctx="${2:?--context needs a value}"
        shift 2
        ;;
      --git-url)
        git_url="${2:?--git-url needs a value}"
        shift 2
        ;;
      --git-ref)
        git_ref="${2:?--git-ref needs a value}"
        shift 2
        ;;
      --path)
        git_path="${2:?--path needs a value}"
        shift 2
        ;;
      --dry-run)
        dry=1
        shift
        ;;
      --prune)
        prune=1
        shift
        ;;
      --label)
        label="${2:?--label needs a value}"
        shift 2
        ;;
      -h | --help)
        usage
        return 2
        ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        return 2
        ;;
    esac
  done

  if [[ "$action" == "drift" && ("$dry" -eq 1 || "$prune" -eq 1) ]]; then
    echo "--dry-run/--prune are reconcile-only flags" >&2
    usage
    return 2
  fi

  rm_require_tools kubectl || return 3

  # Resolve the desired-state directory: either a git remote or a local path.
  if [[ -n "$git_url" ]]; then
    dir="$(_git_fetch "$git_url" "$git_ref" "$git_path")" || return $?
  fi
  [[ -n "$dir" ]] || {
    echo "--dir (or --git-url) is required" >&2
    usage
    return 2
  }
  [[ -d "$dir" ]] || {
    log_error "not a directory: $dir"
    return 2
  }

  rm_banner "Day 24 — real GitOps ($action against a live cluster)"

  case "$action" in
    reconcile) cmd_reconcile "$dir" "$ctx" "$ns" "$dry" "$prune" "$label" ;;
    drift) cmd_drift "$dir" "$ctx" "$ns" ;;
  esac
}

main "$@"
