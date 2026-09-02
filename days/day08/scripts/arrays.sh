#!/usr/bin/env bash
# Indexed arrays, associative arrays, and mapfile.
set -euo pipefail

# --- indexed array ---
servers=("web01" "web02" "db01")
servers+=("cache01")
echo "Server count: ${#servers[@]}"
echo "First: ${servers[0]} | Last: ${servers[-1]}"
for s in "${servers[@]}"; do echo "  - $s"; done

# --- associative array (requires: declare -A) ---
declare -A ports=([http]=80 [https]=443 [ssh]=22)
for svc in "${!ports[@]}"; do
  echo "$svc -> ${ports[$svc]}"
done
echo "https port is ${ports[https]}"

# --- mapfile: read lines into an array (keeps values after the loop) ---
_tmp="$(mktemp)"
printf 'one\ntwo\nthree\n' >"$_tmp"
mapfile -t lines <"$_tmp"
rm -f "$_tmp"
echo "Read ${#lines[@]} lines; second is ${lines[1]}"
