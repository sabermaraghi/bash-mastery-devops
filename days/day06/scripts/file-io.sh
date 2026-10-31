#!/usr/bin/env bash
# Redirection, here-docs, and safe file reading.
set -euo pipefail

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
report="$WORKDIR/report.txt"

# > truncates/creates, >> appends
echo "line one" >"$report"
echo "line two" >>"$report"

# here-doc: write a block of text
cat >>"$report" <<'BLOCK'
line three
line four
BLOCK

# 2> sends stderr somewhere; &> sends both streams
ls "$WORKDIR" /no/such/path >"$WORKDIR/out.txt" 2>"$WORKDIR/err.txt" || true

# read a file back, counting lines
count=0
while IFS= read -r line; do
  count=$((count + 1))
  echo "read[$count]: $line"
done <"$report"

echo "Total lines: $count"
echo "Captured stderr bytes: $(wc -c <"$WORKDIR/err.txt")"
