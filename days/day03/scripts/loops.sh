#!/usr/bin/env bash
# Portable loop demo — self-contained, safe to run from anywhere.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- for: a simple list ---
for fruit in apple banana cherry date; do
  echo "I like $fruit"
done

# --- for: over files (globs this script's own directory) ---
for file in "$SCRIPT_DIR"/*.sh; do
  echo "Found script: $(basename "$file")"
done

# --- for: C-style counter ---
for ((i = 1; i <= 5; i++)); do
  echo "Count: $i"
done

# --- while: with a counter ---
count=1
while [[ $count -le 3 ]]; do
  echo "While count: $count"
  count=$((count + 1))
done

# --- while: read input line by line (the safe IFS= read -r pattern) ---
printf 'first line\nsecond line\n' | while IFS= read -r line; do
  echo "Line: $line"
done

# --- until: runs until the condition becomes true ---
seconds=0
until [[ $seconds -ge 3 ]]; do
  echo "Waiting... $seconds"
  seconds=$((seconds + 1))
done
