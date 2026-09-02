#!/usr/bin/env bash
# grep / sed / awk / cut / sort / uniq on a self-contained fixture.
set -euo pipefail

data="$(mktemp)"
trap 'rm -f "$data"' EXIT
cat >"$data" <<'CSV'
alice,admin,200
bob,user,404
carol,admin,200
dave,user,500
alice,admin,500
CSV

echo "--- grep: admin rows ---"
grep ',admin,' "$data"

echo "--- awk: sum of status column ---"
awk -F, '{ sum += $3 } END { print "total:", sum }' "$data"

echo "--- cut+sort+uniq: request count per user ---"
cut -d, -f1 "$data" | sort | uniq -c | sort -nr

echo "--- sed: mask the role column ---"
sed -E 's/,(admin|user),/,***,/' "$data" | head -1
