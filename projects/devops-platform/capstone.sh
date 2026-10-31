#!/usr/bin/env bash
# capstone.sh — the graduation project: stand up a real, GitOps-managed,
# self-healing, cost-observable platform on Kubernetes, reusing the scripts you
# built across the 30 days. This driver is thin on purpose: it orchestrates the
# day scripts rather than reinventing them.
#
# Layers (see README.md):
#   infra/     provision the cluster + platform add-ons  (Terraform OR bootstrap.sh)
#   gitops/    ArgoCD app-of-apps that declares the services
#   services/  the actual apps (backend + frontend) with their k8s manifests
#
# Subcommands:
#   validate                          offline: every file/manifest is present & sane (CI-safe)
#   up        --context CTX           create cluster + metrics-server + install ArgoCD
#   images    --context CTX           build the service images and load them into kind
#   doctor    --context CTX           diagnose ArgoCD / app health (repo-server, apps, pods)
#   argocd-repair --context CTX [--apply]  resource-patch + restart a flapping repo-server
#   deploy    --context CTX           apply the app-of-apps (ArgoCD manages the rest)
#   operate   --context CTX [--apply] reconcile the WidgetSet CR (Day 26 operator)
#   chaos     --context CTX [--apply] inject a controlled pod failure (Day 28 chaos)
#   heal      --context CTX [--apply] reconcile drift + surface crashloops (Day 29)
#   status    --context CTX           show ArgoCD apps, pods and services
#   cost      --context CTX           run the Day 30 FinOps report over the services
#   down      --context CTX [--all]   remove the apps (--all also deletes the cluster)
#
# Reuses the day scripts directly (no duplication): platform/bootstrap.sh
# (Day 25+), day27 real-argo.sh (ArgoCD), day26 real-operator.sh (operator),
# day28 real-chaos.sh (chaos), day29 real-heal.sh (self-heal), day30
# real-cost.sh (FinOps). Real subcommands need kind/kubectl; they degrade with a
# clear message + exit 3 when a tool or cluster is missing. `validate` needs
# nothing but bash. Mutating steps (operate/chaos/heal) preview by default and
# only change the cluster with --apply.
#
# Exit: 0 ok · 1 validation/deploy problem · 2 usage · 3 missing tool / cluster.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/capstone.log}" COMPONENT="capstone"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"

BOOTSTRAP="$REPO_ROOT/platform/bootstrap.sh"
REAL_ARGO="$REPO_ROOT/days/day27/scripts/real-argo.sh"
REAL_OPERATOR="$REPO_ROOT/days/day26/scripts/real-operator.sh"
REAL_CHAOS="$REPO_ROOT/days/day28/scripts/real-chaos.sh"
REAL_HEAL="$REPO_ROOT/days/day29/scripts/real-heal.sh"
REAL_COST="$REPO_ROOT/days/day30/scripts/real-cost.sh"
KUBECTL="${KUBECTL:-kubectl}"
ROOT_APP="$SCRIPT_DIR/gitops/root.yaml"
WIDGET_CR="$SCRIPT_DIR/ops/widgetset.cr"
WIDGET_NS="widgets"
SERVICE_NS=(backend frontend)

usage() {
  cat >&2 <<'EOF'
usage:
  capstone.sh validate
  capstone.sh up      --context CTX
  capstone.sh images  --context CTX
  capstone.sh doctor  --context CTX
  capstone.sh argocd-repair --context CTX [--apply]
  capstone.sh deploy  --context CTX
  capstone.sh operate --context CTX [--apply]
  capstone.sh chaos   --context CTX [--apply]
  capstone.sh heal    --context CTX [--apply]
  capstone.sh status  --context CTX
  capstone.sh cost    --context CTX
  capstone.sh down    --context CTX [--all]
EOF
  return 2
}

_need_ctx() {
  [[ -n "${CTX:-}" ]] || {
    log_error "--context is required"
    return 2
  }
  return 0
}

_parse_ctx() {
  CTX=""
  ALL=0
  APPLY=0
  while (($#)); do
    case "$1" in
      --context)
        CTX="${2:?"missing value for --context (e.g. --context kind-bash-mastery)"}"
        shift 2
        ;;
      --all)
        ALL=1
        shift
        ;;
      --apply)
        APPLY=1
        shift
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
}

# Echo --apply/--confirm through to a day script only when the user asked for it.
_apply_flags() {
  ((APPLY)) && printf '%s' "--apply --confirm"
}

_check_cluster() {
  if ! "$KUBECTL" --context "$CTX" version --request-timeout=10s >/dev/null 2>&1; then
    log_error "cluster unreachable via context '$CTX' (try: capstone.sh up --context $CTX)"
    return 3
  fi
  return 0
}

# The 'widgets' namespace has no owner. backend/frontend arrive through ArgoCD
# Applications carrying syncOptions CreateNamespace=true, but the Day 26
# operator step is deliberately NOT GitOps-managed: real-operator.sh only runs
# 'kubectl --namespace widgets apply -f -', and kubectl never creates a missing
# namespace. On a long-lived cluster the namespace survived from an earlier run,
# so this stayed hidden; on a freshly rebuilt cluster it fails with:
#   Error from server (NotFound): error when creating "STDIN":
#   namespaces "widgets" not found
# Preparing the environment is the orchestrator's job, so it belongs here — the
# day script stays a pure reconciler.
_ensure_ns() {
  local ns="$1"
  "$KUBECTL" --context "$CTX" get namespace "$ns" >/dev/null 2>&1 && return 0
  if ((APPLY)); then
    log_info "namespace '$ns' is missing — creating it"
    "$KUBECTL" --context "$CTX" create namespace "$ns" --dry-run=client -o yaml |
      "$KUBECTL" --context "$CTX" apply -f - || {
      log_error "could not create namespace '$ns'"
      return 1
    }
    return 0
  fi
  # A preview must not mutate the cluster, but a server dry-run into a missing
  # namespace fails as well — so explain it instead of leaking a raw NotFound.
  log_info "warning: namespace '$ns' does not exist yet; this preview will fail until you rerun with --apply, which creates it"
  return 0
}

# ArgoCD renders manifests inside argocd-repo-server. While that Deployment is
# not Available, the application-controller cannot reach it on :8081 and EVERY
# Application reports:
#   ComparisonError: failed to generate manifest for source 1 of 1: rpc error:
#   code = Unavailable ... dial tcp <clusterIP>:8081: connect: connection refused
# That is a control-plane readiness problem, not a manifest problem — so wait for
# ArgoCD to be Available before applying (and before believing) anything.
# Why is an ArgoCD pod missing? Restart counts and the LAST exit reason answer
# it in one line. OOMKilled/137 on the repo-server is the classic kind-on-a-
# laptop failure: it is the biggest memory consumer (git clone + manifest
# render), so a squeezed node kills it first and :8081 starts refusing.
_argocd_diag() {
  local ns="${ARGOCD_NS:-argocd}"
  echo "-- ArgoCD pods: restarts and why they last died --"
  "$KUBECTL" --context "$CTX" -n "$ns" get pods \
    -o 'custom-columns=POD:.metadata.name,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,LAST_EXIT:.status.containerStatuses[*].lastState.terminated.reason,CODE:.status.containerStatuses[*].lastState.terminated.exitCode' \
    2>/dev/null | sed 's/^/   /' || echo "   (could not read pods in namespace '$ns')"
  echo "-- node pressure (a full node evicts/OOM-kills the repo-server first) --"
  "$KUBECTL" --context "$CTX" get nodes \
    -o 'custom-columns=NODE:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,MEM_PRESSURE:.status.conditions[?(@.type=="MemoryPressure")].status,DISK_PRESSURE:.status.conditions[?(@.type=="DiskPressure")].status' \
    2>/dev/null | sed 's/^/   /' || true
  return 0
}

_wait_argocd() {
  local ns="${ARGOCD_NS:-argocd}" timeout="${ARGOCD_TIMEOUT:-180s}" d rc=0
  if ! "$KUBECTL" --context "$CTX" -n "$ns" get deploy argocd-repo-server >/dev/null 2>&1; then
    log_error "ArgoCD is not installed in namespace '$ns' (run: capstone.sh up --context $CTX)"
    return 3
  fi
  for d in argocd-repo-server argocd-server argocd-applicationset-controller argocd-redis argocd-dex-server; do
    "$KUBECTL" --context "$CTX" -n "$ns" get deploy "$d" >/dev/null 2>&1 || continue
    log_info "waiting for $d to become Available (timeout $timeout)"
    "$KUBECTL" --context "$CTX" -n "$ns" rollout status "deploy/$d" --timeout="$timeout" >/dev/null 2>&1 || rc=1
  done
  if "$KUBECTL" --context "$CTX" -n "$ns" get statefulset argocd-application-controller >/dev/null 2>&1; then
    "$KUBECTL" --context "$CTX" -n "$ns" rollout status statefulset/argocd-application-controller \
      --timeout="$timeout" >/dev/null 2>&1 || rc=1
  fi
  if ((rc)); then
    log_error "ArgoCD control plane is not ready — diagnosing before giving up"
    _argocd_diag
    log_error "a missing repo-server cannot resolve the repo revision: apps keep their last known Health but Sync goes Unknown with ':8081 connection refused'"
    log_error "if LAST_EXIT is OOMKilled (CODE 137) run: capstone.sh argocd-repair --context $CTX --apply"
    log_error "full picture: capstone.sh doctor --context $CTX"
    return 1
  fi
  log_info "ArgoCD control plane is ready"
  return 0
}

# ---- validate (offline, CI-safe) -------------------------------------------
cmd_validate() {
  local ok=1 f
  local required=(
    "$SCRIPT_DIR/README.md"
    "$SCRIPT_DIR/gitops/root.yaml"
    "$SCRIPT_DIR/gitops/apps/backend.yaml"
    "$SCRIPT_DIR/gitops/apps/frontend.yaml"
    "$SCRIPT_DIR/services/backend/Dockerfile"
    "$SCRIPT_DIR/services/backend/app/server.sh"
    "$SCRIPT_DIR/services/backend/k8s/deployment.yaml"
    "$SCRIPT_DIR/services/backend/k8s/service.yaml"
    "$SCRIPT_DIR/services/frontend/Dockerfile"
    "$SCRIPT_DIR/services/frontend/app/index.html"
    "$SCRIPT_DIR/services/frontend/k8s/deployment.yaml"
    "$SCRIPT_DIR/services/frontend/k8s/service.yaml"
    "$SCRIPT_DIR/infra/main.tf"
    "$SCRIPT_DIR/ops/widgetset.cr"
  )
  echo "validating capstone layout…"
  for f in "${required[@]}"; do
    if [[ -f "$f" ]]; then
      printf '  ok   %s\n' "${f#$REPO_ROOT/}"
    else
      printf '  MISS %s\n' "${f#$REPO_ROOT/}"
      ok=0
    fi
  done

  # The bash service must parse.
  if bash -n "$SCRIPT_DIR/services/backend/app/server.sh" 2>/dev/null; then
    printf '  ok   backend server.sh parses\n'
  else
    printf '  FAIL backend server.sh has a syntax error\n'
    ok=0
  fi

  # Every k8s manifest and ArgoCD app declares a kind:.
  for f in "$SCRIPT_DIR"/gitops/root.yaml "$SCRIPT_DIR"/gitops/apps/*.yaml \
    "$SCRIPT_DIR"/services/*/k8s/*.yaml; do
    if grep -q '^kind:' "$f"; then
      printf '  ok   manifest %s\n' "${f#$SCRIPT_DIR/}"
    else
      printf '  FAIL manifest missing kind: %s\n' "${f#$SCRIPT_DIR/}"
      ok=0
    fi
  done

  if ((ok)); then
    echo "RESULT: capstone layout is valid"
    return 0
  fi
  echo "RESULT: capstone layout has problems"
  return 1
}

# ---- up ---------------------------------------------------------------------
cmd_up() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  rm_banner "capstone up — cluster + metrics + ArgoCD"
  local name="${CTX#kind-}"
  log_info "bootstrapping cluster '$name' with metrics-server"
  bash "$BOOTSTRAP" up --name "$name" --metrics >/dev/null || return 3
  # real-argo.sh install previews by default; the capstone genuinely wants the
  # install, so ask for it explicitly (without --apply nothing was ever created,
  # which is why `deploy` could hit an empty argocd namespace).
  log_info "installing ArgoCD"
  bash "$REAL_ARGO" install --context "$CTX" --apply --confirm || return 3
  _wait_argocd || return 1
  log_info "platform ready — next: capstone.sh images --context $CTX && capstone.sh deploy --context $CTX"
  return 0
}

# ---- images (build + load so pods are not stuck in ErrImagePull) ------------
cmd_images() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  rm_banner "capstone images — build + load service images into kind"
  local docker="${DOCKER:-docker}" kind="${KIND:-kind}" name="${CTX#kind-}"
  command -v "$docker" >/dev/null 2>&1 || {
    log_error "'$docker' not found (needed to build the images)"
    return 3
  }
  command -v "$kind" >/dev/null 2>&1 || {
    log_error "'$kind' not found (needed to load images into the cluster)"
    return 3
  }
  local svc tag
  for svc in "${SERVICE_NS[@]}"; do
    tag="devops-platform/${svc}:${IMAGE_TAG:-1.0.0}"
    log_info "building $tag"
    "$docker" build -t "$tag" "$SCRIPT_DIR/services/$svc" || return 1
    log_info "loading $tag into kind cluster '$name'"
    "$kind" load docker-image "$tag" --name "$name" || return 1
  done
  log_info "images available in-cluster — restart the workloads to pick them up: kubectl --context $CTX -n backend rollout restart deploy/backend"
  return 0
}

# ---- argocd-repair (the repo-server keeps dying) ----------------------------
cmd_argocd_repair() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  _check_cluster || return 3
  rm_banner "capstone argocd-repair — give the repo-server room, then restart it"
  local ns="${ARGOCD_NS:-argocd}" timeout="${ARGOCD_TIMEOUT:-180s}"
  local mem="${ARGOCD_REPO_MEM:-1Gi}" cpu="${ARGOCD_REPO_CPU:-500m}"
  if ! "$KUBECTL" --context "$CTX" -n "$ns" get deploy argocd-repo-server >/dev/null 2>&1; then
    log_error "ArgoCD is not installed in namespace '$ns' (run: capstone.sh up --context $CTX)"
    return 3
  fi
  local patch
  patch="$(printf '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-repo-server","resources":{"requests":{"cpu":"100m","memory":"256Mi"},"limits":{"cpu":"%s","memory":"%s"}}}]}}}}' "$cpu" "$mem")"
  _argocd_diag
  if ((!APPLY)); then
    log_info "preview only — would patch argocd-repo-server and restart it:"
    echo "  $patch"
    log_info "re-run with --apply to change the cluster (tune with ARGOCD_REPO_MEM / ARGOCD_REPO_CPU)"
    return 0
  fi
  log_info "patching argocd-repo-server (requests 100m/256Mi, limits $cpu/$mem)"
  "$KUBECTL" --context "$CTX" -n "$ns" patch deploy argocd-repo-server --type=strategic -p "$patch" || return 1
  "$KUBECTL" --context "$CTX" -n "$ns" rollout restart deploy/argocd-repo-server || return 1
  log_info "waiting for argocd-repo-server to become Available (timeout $timeout)"
  if ! "$KUBECTL" --context "$CTX" -n "$ns" rollout status deploy/argocd-repo-server --timeout="$timeout" >/dev/null 2>&1; then
    log_error "argocd-repo-server is still not Available"
    _argocd_diag
    log_error "if the node itself is out of memory, no limit helps — give the Docker VM more RAM, or drop replicas (see README troubleshooting)"
    return 1
  fi
  log_info "repo-server Available — refresh the apps with: capstone.sh deploy --context $CTX"
  return 0
}

# ---- doctor (why is an Application Degraded / erroring?) --------------------
cmd_doctor() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  _check_cluster || return 3
  local ns="${ARGOCD_NS:-argocd}" app
  echo "== ArgoCD control plane (namespace: $ns) =="
  "$KUBECTL" --context "$CTX" -n "$ns" get deploy,statefulset 2>/dev/null | sed 's/^/  /' ||
    echo "  (ArgoCD not installed — run: capstone.sh up --context $CTX)"
  echo "== ArgoCD pods (a non-Running repo-server explains 8081 connection refused) =="
  "$KUBECTL" --context "$CTX" -n "$ns" get pods -o wide 2>/dev/null | sed 's/^/  /' || true
  echo "== argocd-repo-server recent events =="
  "$KUBECTL" --context "$CTX" -n "$ns" describe deploy argocd-repo-server 2>/dev/null |
    sed -n '/Events:/,$p' | sed 's/^/  /' || true
  echo "== Application conditions =="
  for app in platform-root backend frontend; do
    "$KUBECTL" --context "$CTX" -n "$ns" get application "$app" \
      -o 'jsonpath={.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\t"}{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}{"\n"}' \
      2>/dev/null | sed 's/^/  /' || echo "  (application '$app' not found)"
  done
  echo "== workload pods =="
  local wns
  for wns in "${SERVICE_NS[@]}" "$WIDGET_NS"; do
    echo "-- namespace: $wns"
    "$KUBECTL" --context "$CTX" -n "$wns" get pods 2>/dev/null | sed 's/^/  /' ||
      echo "  (namespace not created yet)"
  done
  echo "== why ArgoCD pods restart =="
  _argocd_diag
  echo "HINT: ImagePullBackOff/ErrImagePull on backend → run: capstone.sh images --context $CTX"
  echo "HINT: CrashLoopBackOff on backend → check the app logs: kubectl --context $CTX -n backend logs deploy/backend --previous"
  echo "HINT: Health OK but Sync Unknown + ':8081 connection refused' → the repo-server is down, not your app"
  echo "HINT: repo-server LAST_EXIT=OOMKilled (CODE 137) → run: capstone.sh argocd-repair --context $CTX --apply"
  return 0
}

# ---- deploy -----------------------------------------------------------------
cmd_deploy() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  rm_banner "capstone deploy — app-of-apps via ArgoCD"
  _check_cluster || return 3
  [[ -f "$ROOT_APP" ]] || {
    log_error "missing $ROOT_APP"
    return 1
  }
  # Applying the root app while repo-server is still starting is what produces
  # the ComparisonError / "dial tcp ...:8081 connection refused" conditions.
  _wait_argocd || return $?
  log_info "applying root Application (ArgoCD will sync backend + frontend)"
  "$KUBECTL" --context "$CTX" apply -f "$ROOT_APP" || return 1
  log_info "applied — watch it converge: capstone.sh status --context $CTX"
  return 0
}

# ---- operate (Day 26 operator) ---------------------------------------------
cmd_operate() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  rm_banner "capstone operate — reconcile WidgetSet CR (Day 26)"
  _check_cluster || return 3
  [[ -f "$WIDGET_CR" ]] || {
    log_error "missing $WIDGET_CR"
    return 1
  }
  _ensure_ns "$WIDGET_NS" || return 1
  log_info "reconciling $WIDGET_CR into namespace $WIDGET_NS (apply=$APPLY)"
  # shellcheck disable=SC2046
  bash "$REAL_OPERATOR" reconcile --cr "$WIDGET_CR" --context "$CTX" \
    --namespace "$WIDGET_NS" $(_apply_flags)
}

# ---- chaos (Day 28 chaos engineering) --------------------------------------
cmd_chaos() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  rm_banner "capstone chaos — controlled pod failure on backend (Day 28)"
  _check_cluster || return 3
  log_info "running chaos experiment on backend (selector app=backend, expect 2, apply=$APPLY)"
  # shellcheck disable=SC2046
  bash "$REAL_CHAOS" run --context "$CTX" --namespace backend \
    --selector app=backend --expect 2 --count 1 --seed 1 $(_apply_flags)
}

# ---- heal (Day 29 self-healing) --------------------------------------------
cmd_heal() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  rm_banner "capstone heal — reconcile drift + surface crashloops (Day 29)"
  _check_cluster || return 3
  log_info "healing backend Deployment back to 2 replicas (apply=$APPLY)"
  # shellcheck disable=SC2046
  bash "$REAL_HEAL" heal --context "$CTX" --namespace backend \
    --deployment backend --replicas 2 $(_apply_flags)
}

# ---- status -----------------------------------------------------------------
cmd_status() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  _check_cluster || return 3
  echo "== ArgoCD Applications =="
  "$KUBECTL" --context "$CTX" -n argocd get applications 2>/dev/null || echo "  (ArgoCD not installed?)"
  local ns
  for ns in "${SERVICE_NS[@]}"; do
    echo "== namespace: $ns =="
    "$KUBECTL" --context "$CTX" -n "$ns" get deploy,pods,svc 2>/dev/null | sed 's/^/  /' ||
      echo "  (namespace not created yet)"
  done
  return 0
}

# ---- cost -------------------------------------------------------------------
cmd_cost() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  _check_cluster || return 3
  local ns rc=0
  for ns in "${SERVICE_NS[@]}"; do
    echo "== cost report: $ns =="
    bash "$REAL_COST" report --context "$CTX" --namespace "$ns" || rc=$?
  done
  return "$rc"
}

# ---- down -------------------------------------------------------------------
cmd_down() {
  _parse_ctx "$@" || return $?
  _need_ctx || return 2
  rm_banner "capstone down"
  if _check_cluster; then
    log_info "removing ArgoCD applications, service namespaces and $WIDGET_NS"
    "$KUBECTL" --context "$CTX" -n argocd delete -f "$SCRIPT_DIR/gitops/apps" --ignore-not-found 2>/dev/null || true
    "$KUBECTL" --context "$CTX" -n argocd delete -f "$ROOT_APP" --ignore-not-found 2>/dev/null || true
    # 'operate' creates the widgets namespace, so teardown has to remove it too;
    # otherwise a stale namespace outlives the cluster's other resources.
    "$KUBECTL" --context "$CTX" delete namespace "${SERVICE_NS[@]}" "$WIDGET_NS" --ignore-not-found --wait=false 2>/dev/null || true
  fi
  if ((ALL)); then
    local name="${CTX#kind-}"
    log_info "deleting kind cluster '$name'"
    bash "$BOOTSTRAP" down --name "$name" || return 3
  fi
  return 0
}

main() {
  local action="${1:-}"
  [[ -n "$action" ]] || {
    usage
    return 2
  }
  shift || true
  case "$action" in
    validate) cmd_validate ;;
    up) cmd_up "$@" ;;
    images) cmd_images "$@" ;;
    doctor) cmd_doctor "$@" ;;
    argocd-repair) cmd_argocd_repair "$@" ;;
    deploy) cmd_deploy "$@" ;;
    operate) cmd_operate "$@" ;;
    chaos) cmd_chaos "$@" ;;
    heal) cmd_heal "$@" ;;
    status) cmd_status "$@" ;;
    cost) cmd_cost "$@" ;;
    down) cmd_down "$@" ;;
    -h | --help) usage ;;
    *)
      echo "unknown subcommand: $action" >&2
      usage
      ;;
  esac
}

main "$@"
