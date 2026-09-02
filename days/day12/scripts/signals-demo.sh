#!/usr/bin/env bash
# Background jobs, PIDs, wait, and signal handling.
set -euo pipefail

cleanup() {
  echo "caught signal - cleaning up"
  exit 0
}
trap cleanup INT TERM

worker() {
  sleep "$1"
  echo "worker($1) finished"
}

# Launch two background jobs, capture their PIDs, then wait for both.
worker 0.2 &
pid1=$!
worker 0.1 &
pid2=$!
echo "started PIDs: $pid1 $pid2"
wait "$pid1" "$pid2"
echo "all workers done"
