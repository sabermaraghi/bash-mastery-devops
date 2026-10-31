#!/usr/bin/env bash
# real-container.sh — Day 22, Option 2 (REAL): actually build, run, inspect, and
# sign a rootless container with podman/buildah/docker (+ cosign), instead of
# the offline dry-run/static-audit default.
#
# It COMPOSES the offline tools rather than replacing them:
#   • build   audits the Containerfile (containerfile-audit.sh, fail-closed)
#             BEFORE building, and enforces pinned image tags (container-lib.sh)
#   • run     delegates to run-rootless.sh for the exact same hardened flags,
#             just for real (no --dry-run)
#   • inspect confirms the built image actually runs as a non-root USER
#   • sign    signs a registry image with cosign (image signing needs a digest
#             ref pushed to a registry); verify checks it
#
# Subcommands:
#   build   <context-dir> <image:tag>     build (after audit) with podman/buildah/docker
#   run     <image:tag> [-- CMD...]        hardened rootless launch (real)
#   inspect <image:tag>                    assert the image's USER is non-root
#   sign    <registry/name@sha256:...>     cosign sign an image by ref
#   verify  <registry/name@sha256:...>     cosign verify an image signature
#
# Environment:
#   COSIGN_KEY / COSIGN_PUBKEY   key paths (default ./cosign.key / ./cosign.pub)
#   COSIGN_PASSWORD              key password for non-interactive signing
#   REAL_ASSUME_YES=1           skip confirmations (CI)
#
# Requires the relevant real tool per subcommand; if missing it prints an
# install hint and exits 3 (never a fake success).
# Exit: 0 ok · 1 failure · 2 usage · 3 missing tools.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day22-real-container.log}" COMPONENT="real-container"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/container-lib.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"

AUDIT="$SCRIPT_DIR/containerfile-audit.sh"
RUNNER="$SCRIPT_DIR/run-rootless.sh"
COSIGN_KEY="${COSIGN_KEY:-./cosign.key}"
COSIGN_PUBKEY="${COSIGN_PUBKEY:-./cosign.pub}"
LAST_COSIGN_ERR=""

# Prefer podman (rootless by design), then buildah, then docker, for building.
detect_builder() {
  if command -v podman >/dev/null 2>&1; then
    echo "podman build"
    return 0
  fi
  if command -v buildah >/dev/null 2>&1; then
    echo "buildah bud"
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    echo "docker build"
    return 0
  fi
  return 1
}

# Gentle heads-up when the engine isn't rootless (this day is about rootless).
_warn_if_rootful() {
  local rt="$1"
  is_rootless "$rt" 2>/dev/null && return 0
  log_warn "$rt is not running rootless by default — for true rootless use podman (or docker rootless mode)"
}

find_containerfile() {
  local ctx="$1" f
  for f in Containerfile Dockerfile; do
    [[ -f "$ctx/$f" ]] && {
      echo "$ctx/$f"
      return 0
    }
  done
  return 1
}

# Run cosign quietly; stash stderr for reporting on failure.
_cosign_try() {
  local out
  if out="$(cosign "$@" 2>&1)"; then
    return 0
  fi
  LAST_COSIGN_ERR="$out"
  return 1
}

_check_pin() {
  local image="$1" rc=0
  require_pinned_tag "$image" || rc=$?
  case "$rc" in
    1)
      log_error "image must include an explicit tag, e.g. ${image}:1.0.0"
      return 1
      ;;
    2) log_warn "image uses :latest — pin a real version for reproducibility" ;;
  esac
  return 0
}

build() {
  local ctx="${1:-}" image="${2:-}"
  [[ -n "$ctx" && -n "$image" ]] || {
    echo "usage: $0 build <context-dir> <image:tag>" >&2
    return 2
  }
  [[ -d "$ctx" ]] || {
    log_error "not a directory: $ctx"
    return 2
  }
  _check_pin "$image" || return 1

  local cf
  cf="$(find_containerfile "$ctx")" || {
    log_error "no Containerfile or Dockerfile found in $ctx"
    return 1
  }
  # Fail-closed: never build an image that fails the security audit.
  log_info "auditing $cf before build (fail-closed)"
  bash "$AUDIT" "$cf" || {
    log_error "Containerfile audit failed — fix violations before building"
    return 1
  }

  local builder
  builder="$(detect_builder)" || {
    log_error "no image builder found (podman, buildah, or docker)"
    rm_install_hint podman >&2
    rm_install_hint buildah >&2
    return 3
  }
  [[ "$builder" == docker* ]] && _warn_if_rootful docker
  log_info "building $image with: $builder (using $cf)"
  # Pass -f explicitly: docker/buildkit only auto-detects a file literally named
  # "Dockerfile", whereas we also accept "Containerfile" (podman's default).
  # shellcheck disable=SC2086
  if $builder -t "$image" -f "$cf" "$ctx"; then
    log_info "built image: $image"
    return 0
  fi
  log_error "image build failed"
  return 1
}

run() {
  local image="${1:-}"
  [[ -n "$image" ]] || {
    echo "usage: $0 run <image:tag> [-- CMD...]" >&2
    return 2
  }
  shift
  local rt
  rt="$(detect_runtime)" || {
    log_error "no container runtime found (podman or docker)"
    rm_install_hint podman >&2
    return 3
  }
  _warn_if_rootful "$rt"
  # Delegate to the offline-tested launcher for identical hardening, for real.
  log_info "launching hardened rootless container: $image"
  bash "$RUNNER" "$image" "$@"
}

inspect() {
  local image="${1:-}"
  [[ -n "$image" ]] || {
    echo "usage: $0 inspect <image:tag>" >&2
    return 2
  }
  local rt
  rt="$(detect_runtime)" || {
    log_error "no container runtime found (podman or docker)"
    rm_install_hint podman >&2
    return 3
  }
  local user
  user="$("$rt" image inspect --format '{{.Config.User}}' "$image" 2>/dev/null)" || {
    log_error "image not found locally: $image (build it first)"
    return 1
  }
  if [[ -z "$user" || "$user" == "root" || "$user" == "0" ]]; then
    log_error "image runs as root (USER='${user:-<unset>}') — rebuild with a non-root USER"
    return 1
  fi
  log_info "image USER is non-root: $user"
  return 0
}

sign() {
  local ref="${1:-}"
  [[ -n "$ref" ]] || {
    echo "usage: $0 sign <registry/name@sha256:...>" >&2
    return 2
  }
  rm_require_tools cosign || return 3
  [[ -f "$COSIGN_KEY" ]] || {
    log_error "private key not found: $COSIGN_KEY (reuse Day 18's keygen or set COSIGN_KEY)"
    return 1
  }
  log_info "signing image with cosign: $ref"
  if _cosign_try sign --key "$COSIGN_KEY" --yes --tlog-upload=false "$ref" ||
    _cosign_try sign --key "$COSIGN_KEY" --yes "$ref"; then
    log_info "image signed: $ref"
    return 0
  fi
  log_error "cosign sign failed: ${LAST_COSIGN_ERR:-unknown error}"
  log_error "tip: image signing needs the image pushed to a registry; sign by digest (name@sha256:...)"
  return 1
}

verify() {
  local ref="${1:-}"
  [[ -n "$ref" ]] || {
    echo "usage: $0 verify <registry/name@sha256:...>" >&2
    return 2
  }
  rm_require_tools cosign || return 3
  [[ -f "$COSIGN_PUBKEY" ]] || {
    log_error "public key not found: $COSIGN_PUBKEY (set COSIGN_PUBKEY)"
    return 1
  }
  log_info "verifying image signature with cosign: $ref"
  if _cosign_try verify --key "$COSIGN_PUBKEY" --insecure-ignore-tlog=true "$ref" ||
    _cosign_try verify --key "$COSIGN_PUBKEY" "$ref"; then
    log_info "signature OK: image is authentic"
    return 0
  fi
  log_error "image signature verification FAILED: ${LAST_COSIGN_ERR:-wrong key or unsigned}"
  return 1
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    build | run | inspect | sign | verify) : ;;
    -h | --help)
      echo "usage: $0 {build <ctx> <image:tag> | run <image:tag> [-- CMD...] | inspect <image:tag> | sign <ref> | verify <ref>}"
      return 0
      ;;
    *)
      echo "usage: $0 {build <ctx> <image:tag> | run <image:tag> [-- CMD...] | inspect <image:tag> | sign <ref> | verify <ref>}" >&2
      return 2
      ;;
  esac

  rm_banner "Day 22 — real rootless containers (podman/buildah + cosign)"
  "$cmd" "$@"
}

main "$@"
