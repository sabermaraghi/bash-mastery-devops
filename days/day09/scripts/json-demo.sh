#!/usr/bin/env bash
# Parse and build JSON with jq (skips gracefully if jq is missing).
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not installed - showing what the script would do."
  echo "Install with: apt-get install jq  (or: brew install jq)"
  exit 0
fi

read -r -d '' payload <<'JSON' || true
{"users":[{"name":"alice","role":"admin"},{"name":"bob","role":"user"}]}
JSON

echo "--- all names ---"
jq -r '.users[].name' <<<"$payload"

echo "--- only admins ---"
jq -r '.users[] | select(.role=="admin") | .name' <<<"$payload"

echo "--- build a new object ---"
jq -n --arg host "api.example.com" '{endpoint:$host, ok:true}'
