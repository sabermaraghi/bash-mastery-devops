#!/usr/bin/env bash
# Using /usr/bin/env is preferable since /bin/bash might not be available in certain environments, like containers.
# File: scripts/advanced/day8/monitor.sh
# Purpose: Monitor CPU/MEM of a process with graceful shutdown
set -euo pipefail

# === Configuration ===
TARGET_PID=${1:-$$}           # Default: monitor self # Use $1 (first argument) if provided; otherwise fall back to $$ (current script PID). For instance: ./monitor.sh 1234
INTERVAL=${2:-5}              # Seconds between checks or runs every 5 seconds.
LOG_FILE="/tmp/process-monitor.log"

# === Logging ===
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [MONITOR] $*" | tee -a "$LOG_FILE"  # Display output in the terminal and append to LOG_FILE using the -a flag.
}

# === Cleanup on exit ===
cleanup() {
  log "Monitor stopped (PID: $$, Target: $TARGET_PID)"
  [[ -f "$LOG_FILE" ]] && echo "Log saved: $LOG_FILE"
}
trap cleanup EXIT SIGINT SIGTERM  # Handles EXIT (script ends, normally or with error), SIGINT (user presses Ctrl+C), and SIGTERM (process terminated, e.g., via kill <PID>)

# === Validate PID ===
if ! kill -0 "$TARGET_PID" 2>/dev/null; then                    # Test if process $TARGET_PID exists and is signalable (signal 0 does nothing)
  echo "Error: PID $TARGET_PID not found or not accessible" >&2
  exit 1
fi

log "Started monitoring PID $TARGET_PID every ${INTERVAL}s"

# === Main loop ===
while kill -0 "$TARGET_PID" 2>/dev/null; do  # While process is alive
  CPU=$(ps -p "$TARGET_PID" -o %cpu --no-headers | awk '{print $1}') # Just give the percentage of CPU usage
  MEM=$(ps -p "$TARGET_PID" -o %mem --no-headers | awk '{print $1}')
  COMM=$(ps -p "$TARGET_PID" -o comm --no-headers)

  log "PID=$TARGET_PID | CMD=$COMM | CPU=$CPU% | MEM=$MEM%"

  sleep "$INTERVAL"
done

log "Process $TARGET_PID has terminated"
