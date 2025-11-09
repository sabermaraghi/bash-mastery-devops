Day 4: Error Handling, Debugging, Traps, Signals, Logging

Goal: Scripts that never crash, always log, and always are debuggable.

## 1. Best Bash settings (always at the beginning of the script)
#!/bin/bash
set -euo pipefail # error → exit, undefined variable → error, pipe fail → error
IFS=$'\n\t' # prevent incorrect word splitting

## 2. Trap
Signal Code Usage
EXIT 0 always executes
ERR - executes on every error
INT 2 Ctrl+C
TERM 15 kill

## 3. Logging
log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a /var/log/bash-script.log
}

log "INFO" "Starting Script"

## 4. Debugging
set -x → display each command before execution
set +x → turn off
bash -x script.sh → run with debug
BASH_XTRACEFD=2 → debug to stderr

## 5. Real Projects (Production-Ready) 

| # | Script | Features|
|---|--------|---------|
| 1 | robust-backup.sh | lock + trap + rollback link |
| 2 | deploy-with-rollback.sh | zero-downtime + auto rollback |
| 3 | health-check-monitor.sh | alert + loop + logging |
| 4 | secure-config-loader.sh | validation + yq + safe defaults |
| 5 | cleanup-with-lock.sh | mkdir lock + prevent race |
| 6 | database-backup-restore.sh | verify + latest symlink |
