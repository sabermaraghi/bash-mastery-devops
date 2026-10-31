#!/usr/bin/env bash
# platform/bootstrap.sh — shared cluster bootstrapper for the REAL (Option 2)
# path of the cluster days (25–30).
#
# It gives every cluster day a single, laptop-friendly way to get a real
# Kubernetes cluster up and reachable:
#
#   up      create a local kind cluster (idempotent) + optional metrics-server
#   down    delete the local kind cluster
#   status  show clusters / nodes / current context
#
# WHY kind by default: kind runs a genuine, conformant Kubernetes cluster inside
# Docker — light enough for an 8 GB laptop, yet the exact same manifests and
# kubectl verbs work on a "real" cluster (EKS/GKE/AKS/on-prem). Nothing here is
# kind-specific beyond `up`/`down`; point any day's --context at a bigger cluster
# and it just works.
#
# Usage:
#   bash platform/bootstrap.sh up     [--name NAME] [--metrics]
#   bash platform/bootstrap.sh down   [--name NAME]
#   bash platform/bootstrap.sh status [--name NAME]
#
#   --name NAME   kind cluster name (default: bash-mastery).
#                 kind exposes it to kubectl as context "kind-NAME".
#   --metrics     also install metrics-server (patched for kind's self-signed
#                 kubelet certs) so `kubectl top` works — used by Day 30 (cost).
#
# Requires kind + kubectl. Missing tool -> clear message + exit 3.
# Exit: 0 ok · 2 usage · 3 missing tool / operation failed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/platform-bootstrap.log}" COMPONENT="bootstrap"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"

KUBECTL="${KUBECTL:-kubectl}"
KIND="${KIND:-kind}"
DEFAULT_NAME="bash-mastery"
METRICS_MANIFEST="https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"

usage() {
  {
    echo "usage: $0 up     [--name NAME] [--metrics]"
    echo "       $0 down   [--name NAME]"
    echo "       $0 status [--name NAME]"
  } >&2
  return 2
}

# Does a kind cluster with this name already exist?
_kind_exists() {
  "$KIND" get clusters 2>/dev/null | grep -qx "$1"
}

# Install metrics-server and patch it for kind's self-signed kubelet certs, so
# `kubectl top nodes/pods` works on a local cluster.
_install_metrics() {
  local ctx="$1"
  log_info "installing metrics-server"
  "$KUBECTL" --context "$ctx" apply -f "$METRICS_MANIFEST" || {
    log_error "metrics-server apply failed"
    return 3
  }
  # kind kubelets serve certs the metrics-server won't trust by default.
  "$KUBECTL" --context "$ctx" -n kube-system patch deployment metrics-server \
    --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || {
    log_warn "could not patch metrics-server (already patched?) — continuing"
  }
  log_info "metrics-server installed (give it ~30s, then: kubectl --context $ctx top nodes)"
  return 0
}

cmd_up() {
  local name="$DEFAULT_NAME" metrics=0
  while (($#)); do
    case "$1" in
      --name)
        name="${2:?--name needs a value}"
        shift 2
        ;;
      --metrics)
        metrics=1
        shift
        ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
  done

  local ctx="kind-$name"
  # Keep stdout clean: all progress/logs go to stderr so `CTX=$(bootstrap up)`
  # captures ONLY the context name. The work runs in the current shell (brace
  # group, not a subshell), so `return` still exits the function and variables
  # persist.
  {
    rm_require_tools "$KIND" "$KUBECTL" || return 3

    if _kind_exists "$name"; then
      log_info "kind cluster '$name' already exists — reusing (context: $ctx)"
    else
      log_info "creating kind cluster '$name' (this takes ~30s…)"
      if ! "$KIND" create cluster --name "$name"; then
        log_error "kind create cluster failed (is Docker running?)"
        return 3
      fi
    fi

    # Prove it's reachable before declaring success.
    if ! "$KUBECTL" --context "$ctx" get nodes >/dev/null 2>&1; then
      log_error "cluster created but unreachable via context $ctx"
      return 3
    fi
    log_info "cluster ready — context: $ctx"

    ((metrics)) && { _install_metrics "$ctx" || return 3; }
  } 1>&2

  # The one line on real stdout: the context, for scripting convenience.
  printf '%s\n' "$ctx"
  return 0
}

cmd_down() {
  local name="$DEFAULT_NAME"
  while (($#)); do
    case "$1" in
      --name)
        name="${2:?--name needs a value}"
        shift 2
        ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
  done

  rm_require_tools "$KIND" || return 3
  if ! _kind_exists "$name"; then
    log_info "kind cluster '$name' does not exist — nothing to do"
    return 0
  fi
  log_info "deleting kind cluster '$name'"
  "$KIND" delete cluster --name "$name" || {
    log_error "kind delete cluster failed"
    return 3
  }
  return 0
}

cmd_status() {
  local name="$DEFAULT_NAME"
  while (($#)); do
    case "$1" in
      --name)
        name="${2:?--name needs a value}"
        shift 2
        ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
  done

  rm_require_tools "$KIND" "$KUBECTL" || return 3
  local ctx="kind-$name"
  echo "kind clusters:"
  "$KIND" get clusters 2>/dev/null | sed 's/^/  /' || true
  echo "current context: $("$KUBECTL" config current-context 2>/dev/null || echo '<none>')"
  if _kind_exists "$name"; then
    echo "nodes in $ctx:"
    "$KUBECTL" --context "$ctx" get nodes 2>/dev/null | sed 's/^/  /' || echo "  (unreachable)"
  fi
  return 0
}

main() {
  local action="${1:-}"
  case "$action" in
    up | down | status) shift ;;
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

  # No banner for `status` (pure read-only convenience). Banner to stderr so
  # `up` can keep stdout clean for the context value.
  [[ "$action" != "status" ]] && rm_banner "platform bootstrap ($action)" >&2

  case "$action" in
    up) cmd_up "$@" ;;
    down) cmd_down "$@" ;;
    status) cmd_status "$@" ;;
  esac
}

main "$@"
