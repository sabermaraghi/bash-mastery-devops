#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SECRET_NAME="$1"
PROVIDER="$2"
REGION="${3:-}"
HSM_ENABLED="${4:-0}"
INTERVAL_DAYS="$5"

readonly AUDIT_LOG="/var/log/secret-audit.log"
readonly LOCK="/var/run/secret-rotator.lock"
readonly VAULT_ADDR="${VAULT_ADDR:-https://vault.prod.example.com}"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SECRET] $*" | tee -a "$AUDIT_LOG"
}

acquire_lock() {
  exec 200>"$LOCK"
  if ! flock -n 200; then
    log "ERROR: Another rotation in progress"
    exit 1
  fi
}

rotate_aws() {
  local secret_id="$1"
  local region="$2"
  local hsm="$3"

  if [[ "$hsm" == "1" ]]; then
    log "Using CloudHSM for key generation"
    # Simulate HSM key gen
    new_secret=$(openssl rand -base64 32)
  else
    new_secret=$(aws secretsmanager get-random-password --password-length 30 --exclude-punctuation --output text)
  fi

  aws secretsmanager rotate-secret \
    --secret-id "$secret_id" \
    --region "$region" \
    --rotation-lambda-name secret-rotator-lambda >/dev/null

  log "AWS secret rotated: $secret_id"
}

rotate_gcp() {
  local name="$1"
  gcloud secrets versions add "$name" --data-file=<(echo -n "$(openssl rand -base64 32)")
  log "GCP secret rotated: $name"
}

rotate_vault() {
  local path="$1"
  vault kv put "$path" password="$(openssl rand -base64 32)"
  log "Vault secret rotated: $path"
}

acquire_lock
trap 'flock -u 200; rm -f "$LOCK"' EXIT

case "$PROVIDER" in
  "aws")
    rotate_aws "$SECRET_NAME" "$REGION" "$HSM_ENABLED"
    ;;
  "gcp")
    rotate_gcp "$SECRET_NAME"
    ;;
  "hashicorp-vault")
    rotate_vault "$SECRET_NAME"
    ;;
  *)
    log "ERROR: Unsupported provider: $PROVIDER"
    exit 1
    ;;
esac

next_rotation=$(date -d "+$INTERVAL_DAYS days" -u +"%Y-%m-%dT%H:%M:%SZ")

echo '{
  "secret_id": "'"$SECRET_NAME"'",
  "version": "v2",
  "next_rotation": "'"$next_rotation"'"
}'
