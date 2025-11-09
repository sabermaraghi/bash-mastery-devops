#!/bin/bash
set -euo pipefail

APP_DIR="/var/www/myapp"
RELEASE_DIR="$APP_DIR/releases/$(date +%Y%m%d%H%M%S)"
CURRENT="$APP_DIR/current"
BACKUP="$APP_DIR/backup"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEPLOY] $*" | tee -a /var/log/deploy.log; }

trap 'log "ERROR" "Deployment failed at line $LINENO"; exit 1' ERR
trap 'log "INFO" "Rollback to previous version performed"; rm -rf "$RELEASE_DIR"; ln -sf "$BACKUP" "$CURRENT" 2>/dev/null || true' EXIT

log "INFO" "Starting deployment"

mkdir -p "$RELEASE_DIR"
cp -r /tmp/new-release/* "$RELEASE_DIR/"

# backup current
[[ -d "$CURRENT" ]] && cp -r "$CURRENT" "$BACKUP/"

# switch
rm -f "$CURRENT"
ln -s "$RELEASE_DIR" "$CURRENT"

log "SUCCESS" "Deployment successful: $RELEASE_DIR"
trap - EXIT  # Cancel automatic rollback
