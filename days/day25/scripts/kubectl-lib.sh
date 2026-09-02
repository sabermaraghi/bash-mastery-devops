#!/usr/bin/env bash
# kubectl-lib.sh — shared safety helpers for kubectl automation (sourced).
#
# The binary is resolved via $KUBECTL (default: kubectl) so these wrappers are
# testable with a stub and swappable for `oc`, `kubectl-1.29`, etc.
set -euo pipefail

# Which client to invoke.
kubectl_bin() { printf '%s' "${KUBECTL:-kubectl}"; }

# The cluster we're currently pointed at.
current_context() {
  "$(kubectl_bin)" config current-context 2>/dev/null
}

# Is CTX a protected (production-like) context? Tokens come from
# $PROTECTED_CONTEXTS (comma-separated; default "prod,production").
#   0 = protected   1 = safe
is_protected_context() {
  local ctx="${1:?context required}" tokens="${PROTECTED_CONTEXTS:-prod,production}"
  local IFS=','
  local t
  for t in $tokens; do
    [[ -n "$t" && "$ctx" == *"$t"* ]] && return 0
  done
  return 1
}

# Validate a Kubernetes namespace name (RFC 1123 label, simplified).
is_valid_namespace() {
  local ns="${1:-}"
  [[ "$ns" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}
