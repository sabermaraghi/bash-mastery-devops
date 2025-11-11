#!/usr/bin/env bash
set -euo pipefail

VERSION="$1"
CANARY="$2"
APP_DIR="/var/www/app"
RELEASE_DIR="$APP_DIR/releases/$VERSION"
CURRENT="$APP_DIR/current"
BLUE="$APP_DIR/blue"
GREEN="$APP_DIR/green"

LOG() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [DEPLOY] $*"; }

# Create release
mkdir -p "$RELEASE_DIR"
cp -r /builds/$VERSION/* "$RELEASE_DIR/"
LOG "Release $VERSION extracted"

# Health check function
health_check() {
  curl -f http://localhost:8000/health || return 1
}

# Switch symlink
switch_to() {
  ln -sfn "$1" "$CURRENT"
  LOG "Switched to $1"
}

# Blue-Green
if [[ "$CANARY" == "true" ]]; then
  switch_to "$RELEASE_DIR"
  if health_check; then
    LOG "Canary deploy OK"
  else
    LOG "Canary failed, rollback"
    exit 1
  fi
else
  [[ -d "$BLUE" ]] && rm -rf "$BLUE"
  [[ -d "$GREEN" ]] && mv "$GREEN" "$BLUE" || true
  mv "$RELEASE_DIR" "$GREEN"
  switch_to "$GREEN"
  if health_check; then
    LOG "Full deploy OK"
  else
    switch_to "$BLUE"
    LOG "Rollback to blue"
    exit 1
  fi
fi
