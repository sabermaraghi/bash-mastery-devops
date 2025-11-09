#!/bin/bash
set -euo pipefail

CONFIG="/etc/myapp/config.yaml"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [CONFIG] $*"; }

validate_config() {
  if ! command -v yq &> /dev/null; then
    log "ERROR" "yq is not installed"
    exit 1
  fi

  if ! yq eval '.database.host' "$CONFIG" > /dev/null 2>&1; then
    log "ERROR" "config file invalid or corrupted"
    exit 1
  fi
}

load_config() {
  DB_HOST=$(yq eval '.database.host' "$CONFIG")
  DB_PORT=$(yq eval '.database.port // 5432' "$CONFIG")
  log "INFO" "Connecting to $DB_HOST:$DB_PORT"
}

trap 'log "ERROR" "Error at line $LINENO"' ERR

validate_config
load_config
log "SUCCESS" "config loaded successfully"
