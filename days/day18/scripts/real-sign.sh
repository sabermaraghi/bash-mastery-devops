#!/usr/bin/env bash
# real-sign.sh — Day 18, Option 2 (REAL): cryptographically sign & verify a build
# artifact with cosign.
#
# The offline default (verify-artifact.sh) proves INTEGRITY with a SHA256SUMS
# manifest — it tells you bytes didn't change, but not WHO produced them. cosign
# adds AUTHENTICITY: it signs the manifest with a private key, so a consumer can
# prove the artifact came from someone holding that key (non-repudiation).
#
# This composes the offline tool rather than replacing it: we sign the very same
# SHA256SUMS manifest verify-artifact.sh produces.
#
# Subcommands:
#   keygen [dir]   generate a cosign key pair (cosign.key + cosign.pub) in dir
#   sign   <dir>   (re)build dir/SHA256SUMS, then sign it
#   verify <dir>   verify the signature against the public key
#
# cosign's blob-signing flags changed across versions (v3 dropped
# --output-signature/--tlog-upload in favour of --bundle/--new-bundle-format).
# Rather than guess from --help, we TRY the modern invocation first and fall
# back to the legacy one automatically, so the same command works on any cosign.
# The signature lands next to the manifest as dir/SHA256SUMS.bundle (modern) or
# dir/SHA256SUMS.sig (legacy).
#
# Environment:
#   COSIGN_KEY       private key path   (default: ./cosign.key)
#   COSIGN_PUBKEY    public  key path   (default: ./cosign.pub)
#   COSIGN_PASSWORD  key password for non-interactive keygen/sign (CI-friendly)
#
# Requires cosign. Missing -> clear message + exit 3 (never a fake success).
# Exit: 0 ok · 1 verification/signing failure · 2 usage · 3 missing tools.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day18-real-sign.log}" COMPONENT="real-sign"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"

VERIFIER="$SCRIPT_DIR/verify-artifact.sh"
COSIGN_KEY="${COSIGN_KEY:-./cosign.key}"
COSIGN_PUBKEY="${COSIGN_PUBKEY:-./cosign.pub}"
LAST_COSIGN_ERR=""

# Run cosign quietly; on failure stash stderr in LAST_COSIGN_ERR for reporting.
_cosign_try() {
  local out
  if out="$(cosign "$@" 2>&1)"; then
    return 0
  fi
  LAST_COSIGN_ERR="$out"
  return 1
}

keygen() {
  local dir="${1:-.}"
  [[ -d "$dir" ]] || {
    log_error "not a directory: $dir"
    return 2
  }
  if [[ -f "$dir/cosign.key" ]]; then
    rm_confirm "cosign.key already exists in $dir — overwrite?" || {
      log_info "keygen cancelled"
      return 0
    }
    rm -f "$dir/cosign.key" "$dir/cosign.pub"
  fi
  # cosign writes cosign.key/cosign.pub into the current directory.
  (cd "$dir" && cosign generate-key-pair)
  log_info "generated key pair in $dir (cosign.key is SECRET — never commit it)"
}

sign() {
  local dir="${1:?dir required}"
  [[ -d "$dir" ]] || {
    log_error "not a directory: $dir"
    return 2
  }
  [[ -f "$COSIGN_KEY" ]] || {
    log_error "private key not found: $COSIGN_KEY (run 'keygen' or set COSIGN_KEY)"
    return 1
  }
  # Compose the offline tool: build the SHA256SUMS manifest we are about to sign.
  bash "$VERIFIER" manifest "$dir"

  local manifest="$dir/SHA256SUMS" bundle="$dir/SHA256SUMS.bundle" sig="$dir/SHA256SUMS.sig"
  rm -f "$bundle" "$sig"
  log_info "signing manifest with cosign ($COSIGN_KEY)"

  # Try, in order of preference, until one works on this cosign version:
  #   modern bundle (offline) -> modern bundle -> legacy sig (offline) -> legacy sig
  if _cosign_try sign-blob --key "$COSIGN_KEY" --yes --tlog-upload=false \
    --bundle "$bundle" --new-bundle-format "$manifest" ||
    _cosign_try sign-blob --key "$COSIGN_KEY" --yes \
      --bundle "$bundle" --new-bundle-format "$manifest"; then
    log_info "signed (bundle format): $bundle"
    return 0
  fi
  rm -f "$bundle"
  if _cosign_try sign-blob --key "$COSIGN_KEY" --yes --tlog-upload=false \
    --output-signature "$sig" "$manifest" ||
    _cosign_try sign-blob --key "$COSIGN_KEY" --yes \
      --output-signature "$sig" "$manifest"; then
    log_info "signed (legacy .sig format): $sig"
    return 0
  fi

  log_error "cosign sign-blob failed: ${LAST_COSIGN_ERR:-unknown error}"
  return 1
}

verify() {
  local dir="${1:?dir required}"
  [[ -d "$dir" ]] || {
    log_error "not a directory: $dir"
    return 2
  }
  [[ -f "$COSIGN_PUBKEY" ]] || {
    log_error "public key not found: $COSIGN_PUBKEY (set COSIGN_PUBKEY)"
    return 1
  }
  local manifest="$dir/SHA256SUMS" bundle="$dir/SHA256SUMS.bundle" sig="$dir/SHA256SUMS.sig"
  [[ -f "$manifest" ]] || {
    log_error "missing manifest in $dir (run 'sign' first)"
    return 1
  }
  log_info "verifying signature with cosign ($COSIGN_PUBKEY)"

  if [[ -f "$bundle" ]]; then
    if _cosign_try verify-blob --key "$COSIGN_PUBKEY" --bundle "$bundle" \
      --new-bundle-format --insecure-ignore-tlog=true "$manifest" ||
      _cosign_try verify-blob --key "$COSIGN_PUBKEY" --bundle "$bundle" \
        --new-bundle-format "$manifest" ||
      _cosign_try verify-blob --key "$COSIGN_PUBKEY" --bundle "$bundle" \
        --insecure-ignore-tlog=true "$manifest" ||
      _cosign_try verify-blob --key "$COSIGN_PUBKEY" --bundle "$bundle" "$manifest"; then
      log_info "signature OK: manifest is authentic and unmodified"
      return 0
    fi
  elif [[ -f "$sig" ]]; then
    if _cosign_try verify-blob --key "$COSIGN_PUBKEY" --signature "$sig" \
      --insecure-ignore-tlog=true "$manifest" ||
      _cosign_try verify-blob --key "$COSIGN_PUBKEY" --signature "$sig" "$manifest"; then
      log_info "signature OK: manifest is authentic and unmodified"
      return 0
    fi
  else
    log_error "missing signature in $dir (run 'sign' first)"
    return 1
  fi

  log_error "signature verification FAILED: wrong key or tampered manifest (${LAST_COSIGN_ERR:-})"
  return 1
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    keygen | sign | verify) : ;;
    -h | --help)
      echo "usage: $0 {keygen [dir] | sign <dir> | verify <dir>}"
      return 0
      ;;
    *)
      echo "usage: $0 {keygen [dir] | sign <dir> | verify <dir>}" >&2
      return 2
      ;;
  esac

  rm_require_tools cosign || return 3
  rm_banner "Day 18 — real artifact signing (cosign)"
  "$cmd" "$@"
}

main "$@"
