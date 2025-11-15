# Day 8: Process Management & Signals in Bash

> **Goal**: Master how Bash handles processes, background jobs, and signals — essential for reliable automation scripts.

## 1. Background Execution

sleep 10 &          # Run in background
echo $!             # PID of last background process
wait $!             # Wait for it

## 2. Job Control

sleep 100 &
jobs -l                 # List with PIDs
fg %1                   # Bring job 1 to foreground
bg %1                   # Send to background

## 3. Signals

Signal,Code,Command
SIGINT,2,Ctrl+C
SIGTERM,15,kill $PID
SIGKILL,9,kill -9 $PID

## 4. trap — Handle Signals

cleanup() { echo "Cleaning up..."; rm -f /tmp/app.lock; }
trap cleanup EXIT SIGINT SIGTERM

## 5. Production Script: monitor.sh

Monitors any PID
Logs CPU/MEM every 5s
Handles SIGINT/SIGTERM gracefully
Uses trap for cleanup


---

## Main Script: Level 3 — `scripts/advanced/day8_scripts/monitor.sh`


mkdir -p scripts/advanced/day8
nano scripts/advanced/day8/monitor.sh
