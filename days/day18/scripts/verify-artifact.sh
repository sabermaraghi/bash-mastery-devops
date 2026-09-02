#!/usr/bin/env bash
# verify-artifact.sh — checksum-based integrity gate for a build artifact tree.
#
# Zero-trust rule: never deploy bytes you haven't verified. Generate a signed
# manifest at build time, then verify it before every downstream step.
#
# Subcommands:
#   manifest <dir>   write <dir>/SHA256SUMS covering every file (except itself)
#   verify   <dir>   recompute and compare; exit 1 on ANY mismatch/missing file
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day18-verify.log}" COMPONENT="verify-artifact"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"

manifest() {
  local dir="${1:?dir required}"
  [[ -d "$dir" ]] || {
    log_error "not a directory: $dir"
    return 2
  }
  # Relative paths (from inside dir) keep the manifest portable across machines.
  (cd "$dir" && find . -type f ! -name SHA256SUMS -print0 |
    sort -z | xargs -0 sha256sum) >"$dir/SHA256SUMS"
  log_info "wrote manifest: $dir/SHA256SUMS ($(wc -l <"$dir/SHA256SUMS") files)"
}

verify() {
  local dir="${1:?dir required}"
  [[ -f "$dir/SHA256SUMS" ]] || {
    log_error "no manifest found: $dir/SHA256SUMS (run 'manifest' first)"
    return 1
  }
  if (cd "$dir" && sha256sum -c --quiet SHA256SUMS); then
    log_info "integrity OK: all files match $dir/SHA256SUMS"
    return 0
  fi
  log_error "integrity FAILED: artifact does not match manifest"
  return 1
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    manifest) manifest "$@" ;;
    verify) verify "$@" ;;
    *)
      echo "usage: $0 {manifest <dir> | verify <dir>}" >&2
      return 2
      ;;
  esac
}

main "$@"
