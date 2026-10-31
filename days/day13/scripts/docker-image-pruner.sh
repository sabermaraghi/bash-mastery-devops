#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"
MAX_DAYS="${MAX_DAYS:-30}"

command -v docker &>/dev/null || {
  echo "ERROR: docker is not installed"
  exit 1
}

prune_image() {
  local img="$1"
  local created
  # .Created is always present on every image, unlike Metadata.LastTagTime
  created=$(docker inspect --format '{{.Created}}' "$img" 2>/dev/null || echo "")
  [[ -z "$created" ]] && return

  local created_epoch days_old
  created_epoch=$(date -d "$created" +%s 2>/dev/null || echo 0)
  [[ "$created_epoch" -eq 0 ]] && return # couldn't parse date, skip rather than misjudge age

  days_old=$((($(date +%s) - created_epoch) / 86400))

  if [[ $days_old -gt $MAX_DAYS ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "Would remove: $img ($days_old days old)"
    else
      echo "Removing old image: $img ($days_old days old)"
      docker rmi "$img" --force
    fi
  fi
}
export -f prune_image
export DRY_RUN MAX_DAYS

images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>")
echo "$images" | xargs -n 1 -P 4 -I {} bash -c 'prune_image "$@"' _ {}

if [[ "$DRY_RUN" != "true" ]]; then
  docker image prune -f >/dev/null
fi
echo "Finished pruning images."
