#!/usr/bin/env bash
# reconcile-cr.sh — one reconcile pass for a single CustomResource.
#
# This is the operator's core: read the CR spec (desired), observe reality,
# converge (create/update/delete pods), then write a status subresource.
# Level-triggered and idempotent — re-running with no spec change is a no-op.
#
# Usage:
#   bash reconcile-cr.sh --cr CR_FILE --state-dir STATE_DIR [--dry-run]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day26-operator.log}" COMPONENT="reconcile-cr"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/operator-lib.sh"

usage() {
  echo "usage: $0 --cr CR_FILE --state-dir STATE_DIR [--dry-run]" >&2
  exit 2
}

main() {
  local cr="" state="" dry=0
  while (($#)); do
    case "$1" in
      --cr)
        cr="${2:?}"
        shift
        ;;
      --state-dir)
        state="${2:?}"
        shift
        ;;
      --dry-run) dry=1 ;;
      -h | --help) usage ;;
      -*)
        echo "unknown flag: $1" >&2
        usage
        ;;
      *) usage ;;
    esac
    shift
  done
  [[ -n "$cr" && -n "$state" ]] || usage
  require_file "$cr" || return 1

  # --- read + validate the CR spec (desired state) ---
  local kind name replicas image
  kind="$(cr_get "$cr" kind || true)"
  name="$(cr_get "$cr" name || true)"
  replicas="$(cr_get "$cr" replicas || true)"
  image="$(cr_get "$cr" image || true)"
  [[ "$kind" == "WidgetSet" ]] || {
    log_error "unsupported kind: '${kind:-<none>}' (want WidgetSet)"
    return 1
  }
  [[ -n "$name" && -n "$image" ]] || {
    log_error "CR missing name or image"
    return 1
  }
  is_uint "$replicas" || {
    log_error "replicas must be a non-negative integer, got '${replicas:-<none>}'"
    return 1
  }

  local pods_dir="$state/pods" status_dir="$state/status"
  ((dry)) || mkdir -p "$pods_dir" "$status_dir"

  # --- converge toward desired ---
  local created=0 updated=0 deleted=0 i pod base idx
  for ((i = 0; i < replicas; i++)); do
    pod="$pods_dir/${name}-${i}"
    if [[ ! -f "$pod" ]]; then
      echo "CREATE ${name}-${i}"
      created=$((created + 1))
      ((dry)) || printf '%s\n' "$image" >"$pod"
    elif [[ "$(cat "$pod")" != "$image" ]]; then
      echo "UPDATE ${name}-${i}"
      updated=$((updated + 1))
      ((dry)) || printf '%s\n' "$image" >"$pod"
    fi
  done

  # scale down: remove pods whose index is >= desired replicas
  if [[ -d "$pods_dir" ]]; then
    shopt -s nullglob
    for pod in "$pods_dir/${name}-"*; do
      base="${pod##*/}"
      idx="${base##*-}"
      [[ "$idx" =~ ^[0-9]+$ ]] || continue
      if ((idx >= replicas)); then
        echo "DELETE ${base}"
        deleted=$((deleted + 1))
        ((dry)) || rm -f "$pod"
      fi
    done
    shopt -u nullglob
  fi

  # --- write status subresource (observed state) ---
  local observed phase="Ready"
  if ((dry)); then
    observed="$(count_pods "$pods_dir" "$name" 2>/dev/null || echo 0)"
    phase="Pending"
  else
    observed="$(count_pods "$pods_dir" "$name")"
    ((observed == replicas)) || phase="Scaling"
    {
      echo "name=$name"
      echo "desiredReplicas=$replicas"
      echo "observedReplicas=$observed"
      echo "readyReplicas=$observed"
      echo "image=$image"
      echo "phase=$phase"
    } >"$status_dir/${name}.status"
  fi

  echo "----------------------------"
  if ((created == 0 && updated == 0 && deleted == 0)); then
    echo "already reconciled: ${name} phase=${phase} replicas=${observed}/${replicas}"
  else
    local mode="reconciled"
    ((dry)) && mode="planned"
    printf '%s: %s (%s created, %s updated, %s deleted) phase=%s\n' \
      "$mode" "$name" "$created" "$updated" "$deleted" "$phase"
  fi
}

main "$@"
