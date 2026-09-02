#!/usr/bin/env bash
# optimize-demo.sh — slow-vs-fast, measured with bench.sh.
#
# Three classic Bash performance wins, each benchmarked so you can see the gap:
#   1. built-in parameter expansion  vs  forking sed/echo
#   2. mapfile  vs  a while-read loop for slurping a file
#   3. counting with mapfile  vs  forking `wc -l`
#
# The lesson: every external command is a fork+exec. In hot loops, staying
# inside the shell (parameter expansion, mapfile, [[ ]]) is often 10-100x faster.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day19-demo.log}" COMPONENT="day19"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/bench.sh"

# --- 1. uppercase a string ------------------------------------------------
upper_fast() {
  local s="hello-world"
  printf '%s' "${s^^}" # built-in, no fork
}
upper_slow() {
  echo "hello-world" | tr '[:lower:]' '[:upper:]' # two forks: echo|tr
}

# --- 2 & 3. read / count a file -------------------------------------------
read_fast() {
  local -a lines
  mapfile -t lines <"$DEMO_FILE" # one read into an array
  printf '%s' "${#lines[@]}"
}
read_slow() {
  local line n=0
  while IFS= read -r line; do n=$((n + 1)); done <"$DEMO_FILE"
  printf '%s' "$n"
}
count_slow() { wc -l <"$DEMO_FILE"; } # fork wc for something the shell knows

main() {
  local iters="${1:-2000}"
  DEMO_FILE="$(mktemp)"
  trap 'rm -f "${DEMO_FILE:-}"' EXIT
  seq 1 500 >"$DEMO_FILE"

  log_info "benchmarking (${iters} iterations each) — lower avg is better"
  echo "# 1) uppercase a string"
  bench "$iters" "builtin \${s^^}" upper_fast
  bench "$iters" "fork echo|tr" upper_slow
  echo "# 2) read a 500-line file"
  bench "$iters" "mapfile" read_fast
  bench "$iters" "while read loop" read_slow
  echo "# 3) count lines"
  bench "$iters" "mapfile length" read_fast
  bench "$iters" "fork wc -l" count_slow

  log_info "rule of thumb: avoid forks in hot loops — prefer builtins & mapfile"
}

main "$@"
