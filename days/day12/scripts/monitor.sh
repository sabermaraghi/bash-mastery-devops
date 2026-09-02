#!/usr/bin/env bash
# Using /usr/bin/env is preferable since /bin/bash might not be available in certain environments, like containers.
# File: scripts/advanced/day8/monitor.sh
# Purpose: Monitor CPU/MEM of a process with graceful shutdown
set -euo pipefail

# === Configuration ===
TARGET_PID=${1:-$$}                              # Default: monitor self # Use $1 (first argument) if provided; otherwise fall back to $$ (current script PID). For instance: ./monitor.sh 1234
INTERVAL=${2:-5}                                 # Seconds between checks or runs every 5 seconds.
LOG_FILE="${LOG_FILE:-/tmp/process-monitor.log}" # Overridable so tests (and other callers) can redirect it instead of sharing one global file.

# If the log path isn't writable, fall back to stdout-only instead of letting
# `tee` fail. With `set -euo pipefail` a failing tee kills the whole script, so
# an unwritable log would stop the monitor rather than just losing the file.
if ! { [[ -w "$LOG_FILE" ]] ||
  { [[ ! -e "$LOG_FILE" ]] && [[ -w "$(dirname "$LOG_FILE")" ]]; }; }; then
  LOG_FILE="/dev/null"
fi

# === Logging ===
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [MONITOR] $*" | tee -a "$LOG_FILE" # Display output in the terminal and append to LOG_FILE using the -a flag.
}

# === Cleanup on exit ===
cleanup() {
  local rc=$? # Capture the real exit status FIRST, before running anything else.
  log "Monitor stopped (PID: $$, Target: $TARGET_PID)"
  if [[ -f "$LOG_FILE" ]]; then
    echo "Log saved: $LOG_FILE"
  fi
  # An EXIT trap returns the status of its own last command. Written as
  # `[[ -f "$LOG_FILE" ]] && echo ...`, a missing log file would make the trap
  # return 1 and silently overwrite a successful exit code. Returning the
  # captured $rc keeps the script's real result intact.
  return $rc
}
trap cleanup EXIT # Runs on any exit: normal, error, or via the signal handlers below.

# === Signal handling ===
# A signal trap that only *returns* does not stop the script — bash resumes
# execution right where it was interrupted. Attaching `cleanup` directly to
# SIGINT/SIGTERM therefore printed "Monitor stopped" and then carried on
# monitoring. The handler has to exit; that exit then fires the EXIT trap above,
# so cleanup still runs exactly once.
#
# 128 + signal number is the shell convention: 130 for SIGINT (2),
# 143 for SIGTERM (15).
trap 'log "Received SIGINT — shutting down"; exit 130' SIGINT
trap 'log "Received SIGTERM — shutting down"; exit 143' SIGTERM

# === Validate PID ===
if ! kill -0 "$TARGET_PID" 2>/dev/null; then # Test if process $TARGET_PID exists and is signalable (signal 0 does nothing)
  echo "Error: PID $TARGET_PID not found or not accessible" >&2
  exit 1
fi

log "Started monitoring PID $TARGET_PID every ${INTERVAL}s"

# === Main loop ===
while kill -0 "$TARGET_PID" 2>/dev/null; do                          # While process is alive
  CPU=$(ps -p "$TARGET_PID" -o %cpu --no-headers | awk '{print $1}') # Just give the percentage of CPU usage
  MEM=$(ps -p "$TARGET_PID" -o %mem --no-headers | awk '{print $1}')
  COMM=$(ps -p "$TARGET_PID" -o comm --no-headers)

  log "PID=$TARGET_PID | CMD=$COMM | CPU=$CPU% | MEM=$MEM%"

  sleep "$INTERVAL"
done

log "Process $TARGET_PID has terminated"
