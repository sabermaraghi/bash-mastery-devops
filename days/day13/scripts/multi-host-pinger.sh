#!/usr/bin/env bash
set -euo pipefail

HOSTS_FILE="${1:-/etc/hosts-list.txt}"
THREADS=200

if [[ ! -f "$HOSTS_FILE" ]]; then
  echo "ERROR: hosts file not found: $HOSTS_FILE" >&2
  echo "Usage: $0 <path-to-hosts-file>" >&2
  exit 1
fi

ping_host() {
  local host="$1"
  if ping -c 1 -W 1 "$host" &>/dev/null; then
    echo "UP: $host"
  else
    echo "DOWN: $host" >&2
  fi
}

export -f ping_host
xargs -P "$THREADS" -I {} bash -c 'ping_host "{}"' <"$HOSTS_FILE"
