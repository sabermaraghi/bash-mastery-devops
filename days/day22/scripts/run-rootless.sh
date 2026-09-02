#!/usr/bin/env bash
# run-rootless.sh — launch a container with hardened rootless defaults.
#
# Secure-by-default: read-only rootfs, ALL caps dropped, no new privileges,
# non-root user, network denied unless asked, and pinned image tags only.
# Use --dry-run to print the exact command without executing (works with no
# runtime installed — great for CI and learning).
#
# Usage:
#   bash run-rootless.sh [--dry-run] [--name NAME] [--user UID]
#                        [--network NET] IMAGE[:TAG] [-- CMD...]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day22-run.log}" COMPONENT="run-rootless"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/container-lib.sh"

usage() {
  echo "usage: $0 [--dry-run] [--name NAME] [--user UID] [--network NET] IMAGE[:TAG] [-- CMD...]" >&2
  exit 2
}

main() {
  local dry=0 name="" uid=1000 network="none"
  while (($#)); do
    case "$1" in
      --dry-run) dry=1 ;;
      --name)
        name="${2:?}"
        shift
        ;;
      --user)
        uid="${2:?}"
        shift
        ;;
      --network)
        network="${2:?}"
        shift
        ;;
      --)
        shift
        break
        ;;
      -h | --help) usage ;;
      -*)
        echo "unknown flag: $1" >&2
        usage
        ;;
      *)
        if [[ -z "${image:-}" ]]; then image="$1"; else break; fi
        ;;
    esac
    shift
  done
  local -a cmd_args=("$@")

  [[ -n "${image:-}" ]] || usage
  [[ "$uid" =~ ^[0-9]+$ ]] || {
    log_error "--user must be a numeric UID"
    return 1
  }
  ((uid != 0)) || {
    log_error "refusing to run as root (uid 0); rootless means non-root"
    return 1
  }

  require_pinned_tag "$image"
  case $? in
    1)
      log_error "image must include an explicit tag, e.g. ${image}:1.2.3"
      return 1
      ;;
    2) log_warn "image uses :latest — pin a real version for reproducibility" ;;
  esac

  local rt
  if ! rt="$(detect_runtime)"; then
    if ((dry)); then
      rt="podman"
      log_warn "no runtime found; showing dry-run with podman"
    else
      log_error "no container runtime (podman/docker) found"
      return 1
    fi
  fi

  local -a cmd=(
    "$rt" run --rm
    --read-only
    --cap-drop=ALL
    --security-opt=no-new-privileges
    --pids-limit=256
    --memory=256m
    --network="$network"
    --user "$uid"
  )
  [[ -n "$name" ]] && cmd+=(--name "$name")
  cmd+=("$image")
  ((${#cmd_args[@]})) && cmd+=("${cmd_args[@]}")

  if ((dry)); then
    printf '%q ' "${cmd[@]}"
    printf '\n'
  else
    log_info "launching rootless container: $image"
    exec "${cmd[@]}"
  fi
}

main "$@"
