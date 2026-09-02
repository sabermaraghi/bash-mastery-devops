#!/usr/bin/env bash
# server.sh — the backend IS a Bash script. A tiny HTTP service that answers
# health checks and a JSON payload, proving the whole course comes full circle:
# from `echo` on Day 1 to a containerised, GitOps-deployed microservice in Bash.
#
# Uses busybox `nc` (present in the alpine image) to accept one connection at a
# time. Not a production web server — a teaching one — but it speaks real HTTP
# and passes real Kubernetes liveness/readiness probes.
#
# Two things make this work inside a container, and both were bugs before:
#   1. busybox nc has NO `-q` flag (that is GNU/OpenBSD netcat). Passing it made
#      nc exit instantly with a usage error; the `|| true` swallowed it and the
#      script spun in a tight loop, never listening → probes failed → the pod
#      crash-looped.
#   2. The request must be read from the SOCKET, not from the container's stdin.
#      A FIFO carries nc's stdout (the client request) back into the handler,
#      whose stdout (the response) is piped into nc's stdin.
#
# Env: PORT (8080) · APP_VERSION (1.0.0) · NC_BIN (nc) · BACKEND_FIFO · REQUEST_TIMEOUT
set -euo pipefail
PORT="${PORT:-8080}"
VERSION="${APP_VERSION:-1.0.0}"
NC_BIN="${NC_BIN:-nc}"
BACKEND_FIFO="${BACKEND_FIFO:-/tmp/backend-$$.sock}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-5}"

# Route table: prints the body for a known path, fails for anything else.
route() {
  case "$1" in
    /healthz | /readyz) printf '{"status":"ok"}' ;;
    /) printf '{"service":"backend","version":"%s","status":"ok"}' "$VERSION" ;;
    *) return 1 ;;
  esac
}

# Write a complete HTTP/1.1 response for a path to stdout.
respond() {
  local path="$1" body status='200 OK'
  if ! body="$(route "$path")"; then
    status='404 Not Found'
    body='{"error":"not found"}'
  fi
  printf 'HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
    "$status" "${#body}" "$body"
}

# Read ONE full HTTP request from stdin (request line + headers, up to the blank
# line) and write the response to stdout. Draining the whole header block is not
# cosmetic: bailing out after the request line closes the pipe under nc's feet,
# so the client can see a truncated response and the probe fails.
handle_request() {
  local line target='/' seen_request_line=0 method path proto
  while IFS= read -r -t "$REQUEST_TIMEOUT" line; do
    line="${line%$'\r'}"
    if ((!seen_request_line)) && [[ -n "$line" ]]; then
      seen_request_line=1
      read -r method path proto <<<"$line" || true
      [[ -n "${path:-}" ]] && target="$path"
    fi
    [[ -z "$line" ]] && break
  done
  respond "$target"
}

cleanup() {
  rm -f "$BACKEND_FIFO"
}

serve() {
  rm -f "$BACKEND_FIFO"
  mkfifo "$BACKEND_FIFO"
  trap 'cleanup; exit 0' INT TERM
  trap cleanup EXIT
  echo "backend (bash) listening on :$PORT" >&2
  while true; do
    # nc stdout (client request) → FIFO → handler stdin
    # handler stdout (response)  → pipe → nc stdin → client
    handle_request <"$BACKEND_FIFO" | "$NC_BIN" -l -p "$PORT" >"$BACKEND_FIFO" || true
  done
}

# Only serve when executed. Sourcing the script (the BATS suite does) just loads
# route/respond/handle_request so they can be tested without a socket.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  serve
fi
