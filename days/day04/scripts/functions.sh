#!/usr/bin/env bash
set -euo pipefail

# Basic function with a local variable and a timestamp.
greet() {
  local name="$1"
  local timestamp
  timestamp=$(date +%F_%H:%M:%S)
  echo "[$timestamp] Hello, $name! Welcome to Bash mastery."
}
greet "DevOps Engineer"

# "Return" a value by echoing it and capturing with $(...).
add() {
  local a=$1 b=$2
  echo $((a + b))
}
result=$(add 15 27)
echo "15 + 27 = $result"

# Default arguments: ${1:-default}.
backup() {
  local src="${1:-/home}" dest="${2:-/backup}"
  echo "Backing up $src -> $dest"
}
backup
backup /etc /var/backup

# Return an array via a global (bash functions can't return arrays directly).
get_system_info() {
  local info=()
  info+=("user:${USER:-$(id -un 2>/dev/null || echo unknown)}")
  info+=("host:${HOSTNAME:-$(uname -n 2>/dev/null || echo unknown)}")
  SYSTEM_INFO=("${info[@]}")
}
get_system_info
echo "System info collected:" "${SYSTEM_INFO[@]}"
