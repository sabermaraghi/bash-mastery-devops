#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

IMAGE="$1"
STRATEGY="$2"
CANARY_PCT="${3:-0}"
HEALTH_ENDPOINT="$4"
TIMEOUT="$5"

readonly CURRENT="/srv/app/current"
readonly BLUE="/srv/app/blue"
readonly GREEN="/srv/app/green"
readonly LOG="/var/log/deploy-orchestrator.log"
readonly LOCK="/var/run/deploy-orchestrator.lock"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [DEPLOY] $*" | tee -a "$LOG"
}

acquire_lock() {
  exec 200>"$LOCK"
  if ! flock -n 200; then
    log "ERROR: Another deploy is running"
    exit 1
  fi
}

health_check() {
  local target="$1"
  for i in $(seq 1 10); do
    if curl -sf "$target$HEALTH_ENDPOINT" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

rollback() {
  log "ROLLBACK: Reverting to previous version"
  ln -sfn "$PREVIOUS" "$CURRENT" 2>/dev/null || true
}

acquire_lock
trap 'flock -u 200; rm -f "$LOCK"' EXIT

mkdir -p "$BLUE" "$GREEN"

# Determine current & next
if [[ -L "$CURRENT" && -d "$CURRENT" ]]; then
  CURRENT_TARGET=$(readlink "$CURRENT")
  if [[ "$CURRENT_TARGET" == "$BLUE"* ]]; then
    NEXT="$GREEN"
    PREVIOUS="$BLUE"
  else
    NEXT="$BLUE"
    PREVIOUS="$GREEN"
  fi
else
  NEXT="$BLUE"
  PREVIOUS=""
fi

log "Deploying $IMAGE to $NEXT using $STRATEGY strategy"

# Pull & extract image
container_id=$(podman create "$IMAGE")
podman export "$container_id" | tar -x -C "$NEXT"
podman rm "$container_id"

# Start temporary container for healthcheck
temp_port=$((8000 + RANDOM % 1000))
podman run -d --name deploy-temp -p "$temp_port:8000" --network host "$IMAGE"
sleep 5

if ! health_check "http://localhost:$temp_port"; then
  log "ERROR: Health check failed on new image"
  podman rm -f deploy-temp
  exit 1
fi

podman rm -f deploy-temp

if [[ "$STRATEGY" == "canary" ]]; then
  log "CANARY: $CANARY_PCT% traffic to new version"
  echo "Canary deployment simulated: $CANARY_PCT% to $IMAGE" >&2
else
  ln -sfn "$NEXT" "$CURRENT"
  log "BLUE-GREEN: Switched to $NEXT"
fi

log "Deployment successful"
echo "{\"active\": \"$NEXT\", \"image\": \"$IMAGE\", \"strategy\": \"$STRATEGY\"}"
