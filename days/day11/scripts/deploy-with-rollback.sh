#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/var/www/myapp"
RELEASE_DIR="$APP_DIR/releases/$(date +%Y%m%d%H%M%S)"
CURRENT="$APP_DIR/current"
BACKUP="$APP_DIR/backup"

log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEPLOY] [$level] $*" | tee -a /var/log/deploy.log
}

trap 'log "ERROR" "Deployment failed at line $LINENO"; exit 1' ERR
trap '
  if [[ -d "$BACKUP" ]]; then
    log "INFO" "Rolling back to previous release"
    ln -sf "$BACKUP" "$CURRENT"
  else
    log "INFO" "No previous release to roll back to"
  fi
  rm -rf "$RELEASE_DIR"
' EXIT

log "INFO" "Starting deployment"

mkdir -p "$RELEASE_DIR"
cp -r /tmp/new-release/. "$RELEASE_DIR/"

# backup current
if [[ -d "$CURRENT" ]]; then
  rm -rf "$BACKUP"
  mkdir -p "$BACKUP"
  cp -r "$CURRENT/." "$BACKUP/"
fi

# switch
rm -f "$CURRENT"
ln -s "$RELEASE_DIR" "$CURRENT"

log "SUCCESS" "Deployment successful: $RELEASE_DIR"
trap - EXIT # Cancel automatic rollback
