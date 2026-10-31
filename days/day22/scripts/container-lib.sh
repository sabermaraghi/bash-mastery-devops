#!/usr/bin/env bash
# container-lib.sh — sourced helpers for rootless container work.
#
# Pure, runtime-optional helpers so scripts (and tests) behave the same whether
# or not podman/docker is installed. Source it:
#   source container-lib.sh
set -euo pipefail

# Echo the preferred runtime name (podman first — rootless by design), or fail.
detect_runtime() {
  if command -v podman >/dev/null 2>&1; then
    echo podman
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    echo docker
    return 0
  fi
  return 1
}

# Is this runtime operating rootless? Best-effort, never fatal.
is_rootless() {
  local rt="${1:?runtime required}"
  case "$rt" in
    podman) [[ "$(id -u)" -ne 0 ]] ;; # podman is rootless for any non-root user
    docker)
      if docker info 2>/dev/null | grep -qi 'rootless'; then return 0; fi
      [[ "${DOCKER_HOST:-}" == *rootless* || "${DOCKER_HOST:-}" == *"/user/"* ]]
      ;;
    *) return 2 ;;
  esac
}

# Validate that an image reference is pinned to an explicit, non-latest tag.
#   0 = pinned OK   1 = no tag at all   2 = uses :latest
require_pinned_tag() {
  local img="${1:?image required}" tag
  [[ "$img" == *:* ]] || return 1
  tag="${img##*:}"
  [[ "$tag" == */* ]] && return 1 # was registry:port/name, no real tag
  [[ "$tag" == "latest" ]] && return 2
  return 0
}
