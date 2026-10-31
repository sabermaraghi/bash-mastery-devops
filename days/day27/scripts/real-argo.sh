#!/usr/bin/env bash
# real-argo.sh — Option 2 (real) for Day 27: real ArgoCD on a live cluster.
#
# The offline scripts (sync-app.sh / sync-root.sh) imitate ArgoCD by hashing a
# git source dir against a live dir. This version drives the real thing:
#   1. install ArgoCD into the cluster,
#   2. translate our .app manifests into real ArgoCD `Application` CRs,
#   3. apply / sync / inspect them — the genuine GitOps CD control plane.
#
# It reuses the offline manifest parser (argo-lib.sh: app_get) and the Day 25
# kubectl safety rails (kubectl-lib.sh: kubectl_bin, current_context,
# is_protected_context, is_valid_namespace) — same guarantees, real target.
#
# Subcommands:
#   install         --context CTX [--namespace argocd] [--apply] [--confirm]
#   render          --app FILE --repo-url URL [--revision REV] [--dest-namespace NS] [--prune]
#   render-children --repo-url URL [--apps-dir DIR] [--out DIR] [--revision REV] [--prune]
#   apply           --app FILE --context CTX --repo-url URL [--revision REV]
#                   [--namespace argocd] [--dest-namespace NS] [--apply] [--confirm] [--prune]
#   sync            --app FILE --context CTX [--namespace argocd] [--use-cli]
#   status          --app FILE --context CTX [--namespace argocd] [--use-cli]
#   ui              --context CTX [--namespace argocd] [--port 8080]
#   admin-password  --context CTX [--namespace argocd]
#
# `render`/`render-children` are pure translation and need no cluster. Everything
# else talks to the cluster and degrades gracefully (exit 3) when the tool/
# cluster is absent. `sync`/`status` use kubectl by default (no argocd login
# needed); pass --use-cli to use the `argocd` CLI ($ARGOCD) instead.
#
# Exit: 0 ok · 1 apply/guard failure · 2 usage · 3 missing tool / unreachable.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day27-real-argo.log}" COMPONENT="real-argo"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/argo-lib.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/days/day25/scripts/kubectl-lib.sh"

# Official stable install manifest (overridable for air-gapped mirrors).
ARGOCD_MANIFEST="${ARGOCD_MANIFEST:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"
argocd_bin() { printf '%s' "${ARGOCD:-argocd}"; }

usage() {
  cat >&2 <<'EOF'
usage:
  real-argo.sh install         --context CTX [--namespace argocd] [--apply] [--confirm]
  real-argo.sh render          --app FILE --repo-url URL [--revision REV] [--dest-namespace NS] [--prune]
  real-argo.sh render-children --repo-url URL [--apps-dir DIR] [--out DIR] [--revision REV] [--prune]
  real-argo.sh apply           --app FILE --context CTX --repo-url URL [--revision REV] [--namespace argocd] [--dest-namespace NS] [--apply] [--confirm] [--prune]
  real-argo.sh sync            --app FILE --context CTX [--namespace argocd] [--use-cli]
  real-argo.sh status          --app FILE --context CTX [--namespace argocd] [--use-cli]
  real-argo.sh ui              --context CTX [--namespace argocd] [--port 8080]
  real-argo.sh admin-password  --context CTX [--namespace argocd]
EOF
  exit 2
}

_check_cluster() {
  local ctx="$1"
  if ! "$(kubectl_bin)" --context "$ctx" version --request-timeout=10s >/dev/null 2>&1; then
    log_error "cluster unreachable via context '$ctx' (try: bash platform/bootstrap.sh up)"
    return 3
  fi
  return 0
}

# Read + validate an Application manifest into globals.
# Sets APP_NAME; for a leaf also APP_SOURCE/APP_DEST; for a root APP_APPS.
# Sets APP_IS_ROOT=1 when it's an app-of-apps.
_read_app() {
  local app="$1" kind
  [[ -f "$app" ]] || {
    log_error "app manifest not found: $app"
    return 2
  }
  kind="$(app_get "$app" kind || true)"
  APP_NAME="$(app_get "$app" name || true)"
  [[ "$kind" == "Application" ]] || {
    log_error "unsupported kind: '${kind:-<none>}' (want Application)"
    return 2
  }
  [[ -n "$APP_NAME" ]] || {
    log_error "Application missing name"
    return 2
  }
  APP_IS_ROOT=0
  APP_SOURCE=""
  APP_DEST=""
  APP_APPS=""
  if APP_APPS="$(app_get "$app" apps 2>/dev/null)"; then
    APP_IS_ROOT=1
  else
    APP_SOURCE="$(app_get "$app" source || true)"
    APP_DEST="$(app_get "$app" dest || true)"
    [[ -n "$APP_SOURCE" ]] || {
      log_error "leaf Application needs a source path"
      return 2
    }
  fi
  return 0
}

# Emit a real ArgoCD Application CR. Args come from globals + render options.
_render_cr() {
  local repo="$1" rev="$2" argons="$3" destns="$4" prune="$5" path
  if ((APP_IS_ROOT)); then
    path="$APP_APPS"
  else
    path="$APP_SOURCE"
  fi
  local prune_val="false"
  ((prune)) && prune_val="true"
  cat <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: ${argons}
spec:
  project: default
  source:
    repoURL: ${repo}
    targetRevision: ${rev}
    path: ${path}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${destns}
  syncPolicy:
    automated:
      prune: ${prune_val}
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
}

cmd_render() {
  local app="" repo="" rev="HEAD" destns="" prune=0 argons="argocd"
  while (($#)); do
    case "$1" in
      --app)
        app="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --repo-url)
        repo="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --revision)
        rev="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --dest-namespace)
        destns="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --namespace)
        argons="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --prune) prune=1 ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
    shift
  done
  [[ -n "$app" && -n "$repo" ]] || usage
  _read_app "$app" || return $?
  [[ -n "$destns" ]] || destns="$APP_NAME"
  is_valid_namespace "$destns" || {
    log_error "invalid dest namespace: '$destns'"
    return 2
  }
  _render_cr "$repo" "$rev" "$argons" "$destns" "$prune"
  return 0
}

# render-children: turn every leaf *.app into a real committed Application YAML.
# This is what makes the REAL app-of-apps work: the root points at a directory
# of these rendered Application manifests in git.
cmd_render_children() {
  local repo="" rev="HEAD" prune=0 argons="argocd"
  local apps_dir="$REPO_ROOT/days/day27/examples/apps"
  local out="$REPO_ROOT/days/day27/examples/argo-apps"
  while (($#)); do
    case "$1" in
      --repo-url)
        repo="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --apps-dir)
        apps_dir="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --out)
        out="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --revision)
        rev="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --prune) prune=1 ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
    shift
  done
  [[ -n "$repo" ]] || usage
  [[ -d "$apps_dir" ]] || {
    log_error "apps dir not found: $apps_dir"
    return 1
  }
  mkdir -p "$out"
  local child n=0
  shopt -s nullglob
  for child in "$apps_dir"/*.app; do
    _read_app "$child" || return $?
    if ((APP_IS_ROOT)); then
      log_warn "skipping root manifest $(basename "$child")"
      continue
    fi
    _render_cr "$repo" "$rev" "$argons" "$APP_NAME" "$prune" >"$out/${APP_NAME}.yaml"
    echo "WROTE	$out/${APP_NAME}.yaml"
    n=$((n + 1))
  done
  shopt -u nullglob
  ((n > 0)) || {
    log_error "no leaf *.app files in $apps_dir"
    return 1
  }
  log_info "rendered $n child Application manifest(s) into $out — commit + push them, then apply the root"
  return 0
}

cmd_apply() {
  local app="" ctx="" repo="" rev="HEAD" destns="" prune=0 argons="argocd" apply=0 confirm=0
  while (($#)); do
    case "$1" in
      --app)
        app="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --context)
        ctx="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --repo-url)
        repo="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --revision)
        rev="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --dest-namespace)
        destns="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --namespace)
        argons="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --apply) apply=1 ;;
      --confirm) confirm=1 ;;
      --prune) prune=1 ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
    shift
  done
  [[ -n "$app" && -n "$ctx" && -n "$repo" ]] || usage
  _read_app "$app" || return $?
  [[ -n "$destns" ]] || destns="$APP_NAME"
  is_valid_namespace "$argons" || {
    log_error "invalid namespace: '$argons'"
    return 2
  }
  is_valid_namespace "$destns" || {
    log_error "invalid dest namespace: '$destns'"
    return 2
  }
  if is_protected_context "$ctx" && ((!confirm)); then
    log_error "context '$ctx' is protected; re-run with --confirm to proceed"
    return 1
  fi
  _check_cluster "$ctx" || return 3

  local -a k=("$(kubectl_bin)" --context "$ctx" --namespace "$argons" apply -f -)
  if ((apply)); then
    log_info "applying ArgoCD Application/$APP_NAME (repo=$repo path=$( ((APP_IS_ROOT)) && echo "$APP_APPS" || echo "$APP_SOURCE"))"
  else
    k+=(--dry-run=server)
    log_info "preview (server dry-run) Application/$APP_NAME; pass --apply to create"
  fi
  if _render_cr "$repo" "$rev" "$argons" "$destns" "$prune" | "${k[@]}"; then
    return 0
  fi
  log_error "apply failed for Application/$APP_NAME"
  return 1
}

cmd_sync() {
  local app="" ctx="" argons="argocd" use_cli=0
  while (($#)); do
    case "$1" in
      --app)
        app="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --context)
        ctx="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --namespace)
        argons="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --use-cli) use_cli=1 ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
    shift
  done
  [[ -n "$app" && -n "$ctx" ]] || usage
  _read_app "$app" || return $?
  _check_cluster "$ctx" || return 3

  # Default: kubectl-driven (no argocd login required). The automated syncPolicy
  # we set means a hard refresh is enough to make ArgoCD reconcile now.
  if ((use_cli)); then
    command -v "$(argocd_bin)" >/dev/null 2>&1 || {
      log_error "--use-cli given but argocd CLI not found (run 'real-argo.sh ui' + 'argocd login')"
      return 3
    }
    log_info "syncing via argocd CLI: $APP_NAME"
    "$(argocd_bin)" app sync "$APP_NAME" && return 0
    log_error "argocd app sync failed for $APP_NAME (is the CLI logged in? see 'real-argo.sh ui')"
    return 1
  fi
  log_info "requesting a hard refresh via kubectl (automated sync then converges): $APP_NAME"
  if "$(kubectl_bin)" --context "$ctx" --namespace "$argons" annotate application "$APP_NAME" \
    argocd.argoproj.io/refresh=hard --overwrite; then
    return 0
  fi
  log_error "could not trigger refresh for $APP_NAME"
  return 1
}

cmd_status() {
  local app="" ctx="" argons="argocd" use_cli=0
  while (($#)); do
    case "$1" in
      --app)
        app="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --context)
        ctx="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --namespace)
        argons="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --use-cli) use_cli=1 ;;
      -h | --help) usage ;;
      *)
        echo "unknown arg: $1" >&2
        usage
        ;;
    esac
    shift
  done
  [[ -n "$app" && -n "$ctx" ]] || usage
  _read_app "$app" || return $?
  _check_cluster "$ctx" || return 3

  if ((use_cli)); then
    command -v "$(argocd_bin)" >/dev/null 2>&1 || {
      log_error "--use-cli given but argocd CLI not found"
      return 3
    }
    "$(argocd_bin)" app get "$APP_NAME"
    return 0
  fi
  # Does the Application object exist at all?
  if ! "$(kubectl_bin)" --context "$ctx" --namespace "$argons" get application "$APP_NAME" \
    >/dev/null 2>&1; then
    log_warn "Application/$APP_NAME not found in $argons (run apply --apply first)"
    return 0
  fi
  # It exists; ArgoCD may not have reconciled it yet (empty .status right after apply).
  local sync health
  sync="$("$(kubectl_bin)" --context "$ctx" --namespace "$argons" get application "$APP_NAME" \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$("$(kubectl_bin)" --context "$ctx" --namespace "$argons" get application "$APP_NAME" \
    -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  if [[ -z "$sync" && -z "$health" ]]; then
    log_info "Application/$APP_NAME exists but is not reconciled yet - re-run status in a few seconds"
    return 0
  fi
  printf 'Application/%s  sync=%s  health=%s\n' "$APP_NAME" "${sync:-Progressing}" "${health:-Progressing}"
  return 0
}

cmd_install() {
  local ctx="" argons="argocd" apply=0 confirm=0
  while (($#)); do
    case "$1" in
      --context)
        ctx="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --namespace)
        argons="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
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
  [[ -n "$ctx" ]] || usage
  is_valid_namespace "$argons" || {
    log_error "invalid namespace: '$argons'"
    return 2
  }
  if is_protected_context "$ctx" && ((!confirm)); then
    log_error "context '$ctx' is protected; re-run with --confirm to proceed"
    return 1
  fi
  _check_cluster "$ctx" || return 3

  if ((!apply)); then
    log_info "preview only — would create namespace '$argons' and apply ArgoCD from $ARGOCD_MANIFEST (pass --apply to install)"
    return 0
  fi
  log_info "installing ArgoCD into namespace '$argons'"
  "$(kubectl_bin)" --context "$ctx" create namespace "$argons" --dry-run=client -o yaml |
    "$(kubectl_bin)" --context "$ctx" apply -f -
  # ArgoCD's CRDs (e.g. applicationsets.argoproj.io) exceed the 256KB
  # last-applied-configuration annotation limit of a client-side apply, so this
  # must be a server-side apply or it fails with "metadata.annotations: Too
  # long". --force-conflicts lets us re-run install idempotently.
  if "$(kubectl_bin)" --context "$ctx" --namespace "$argons" apply --server-side --force-conflicts -f "$ARGOCD_MANIFEST"; then
    log_info "ArgoCD applied — wait for rollout: kubectl -n $argons rollout status deploy/argocd-server"
    return 0
  fi
  log_error "ArgoCD install failed"
  return 1
}

# ui: port-forward the ArgoCD server so you can log in (browser + CLI).
cmd_ui() {
  local ctx="" argons="argocd" port=8080
  while (($#)); do
    case "$1" in
      --context)
        ctx="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --namespace)
        argons="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --port)
        port="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
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
  [[ -n "$ctx" ]] || usage
  _check_cluster "$ctx" || return 3
  log_info "port-forwarding argocd-server — open https://localhost:${port}  (user: admin)"
  log_info "password: bash days/day27/scripts/real-argo.sh admin-password --context $ctx"
  log_info "CLI login: argocd login localhost:${port} --username admin --password <pw> --insecure"
  log_info "press Ctrl+C to stop the port-forward"
  exec "$(kubectl_bin)" --context "$ctx" --namespace "$argons" port-forward svc/argocd-server "${port}:443"
}

cmd_admin_password() {
  local ctx="" argons="argocd"
  while (($#)); do
    case "$1" in
      --context)
        ctx="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
        shift
        ;;
      --namespace)
        argons="${2:?"missing value for $1 (is the variable set in THIS terminal? e.g. CTX=kind-bash-mastery)"}"
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
  [[ -n "$ctx" ]] || usage
  _check_cluster "$ctx" || return 3
  local enc
  enc="$("$(kubectl_bin)" --context "$ctx" --namespace "$argons" get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null || true)"
  [[ -n "$enc" ]] || {
    log_error "initial admin secret not found (already rotated, or ArgoCD not installed)"
    return 1
  }
  printf '%s\n' "$enc" | base64 --decode
  echo
  return 0
}

main() {
  local action="${1:-}"
  [[ -n "$action" ]] || usage
  shift
  case "$action" in
    install | render | render-children | apply | sync | status | ui | admin-password) ;;
    -h | --help) usage ;;
    *)
      echo "unknown subcommand: $action" >&2
      usage
      ;;
  esac

  # render/render-children are pure translation — no tools required.
  if [[ "$action" != "render" && "$action" != "render-children" ]]; then
    rm_require_tools "$(kubectl_bin)" || return 3
    rm_banner "Day 27 — real ArgoCD ($action) against a live cluster" >&2
  fi

  case "$action" in
    install) cmd_install "$@" ;;
    render) cmd_render "$@" ;;
    render-children) cmd_render_children "$@" ;;
    apply) cmd_apply "$@" ;;
    sync) cmd_sync "$@" ;;
    status) cmd_status "$@" ;;
    ui) cmd_ui "$@" ;;
    admin-password) cmd_admin_password "$@" ;;
  esac
}

main "$@"
