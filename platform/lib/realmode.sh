#!/usr/bin/env bash
# platform/lib/realmode.sh — shared helpers for the "real deployment" path
# (Option 2) across days. The offline simulation (Option 1) is the tested
# default and never sources this file.
#
# Source it, don't execute it:
#   source "$REPO_ROOT/platform/lib/realmode.sh"
#
# Provides:
#   rm_banner <title>            consistent REAL-MODE header
#   rm_install_hint <tool>       prints how to install one known tool
#   rm_require_tools <tool...>   returns 1 (with install hints) if any missing
#   rm_confirm <prompt>          y/N guard; auto-yes when REAL_ASSUME_YES=1

# Best-effort, cross-platform install hint for a known tool.
rm_install_hint() {
  case "${1:-}" in
    gitleaks) echo "  gitleaks : https://github.com/gitleaks/gitleaks/releases  (brew install gitleaks)" ;;
    trivy) echo "  trivy    : https://aquasecurity.github.io/trivy         (brew install trivy)" ;;
    cosign) echo "  cosign   : https://docs.sigstore.dev/cosign/installation (brew install cosign)" ;;
    podman) echo "  podman   : https://podman.io/docs/installation" ;;
    buildah) echo "  buildah  : https://buildah.io/#install" ;;
    kubectl) echo "  kubectl  : https://kubernetes.io/docs/tasks/tools/" ;;
    kind) echo "  kind     : https://kind.sigs.k8s.io/docs/user/quick-start/#installation" ;;
    argocd) echo "  argocd   : https://argo-cd.readthedocs.io/en/stable/cli_installation/" ;;
    *) echo "  ${1:-tool} : see the tool's official documentation" ;;
  esac
}

# Consistent banner so real runs are never mistaken for the offline default.
rm_banner() {
  printf '========================================================\n'
  printf 'REAL MODE  \xc2\xb7  %s\n' "${1:-real deployment}"
  printf 'Offline simulation stays the default \xe2\x80\x94 see the day README.\n'
  printf '========================================================\n'
}

# rm_require_tools tool [tool...] -> 0 if all present, else 1 with hints on stderr.
rm_require_tools() {
  local t missing=()
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    {
      printf 'REAL MODE unavailable \xe2\x80\x94 missing required tool(s): %s\n' "${missing[*]}"
      printf 'Install, then re-run:\n'
      for t in "${missing[@]}"; do rm_install_hint "$t"; done
    } >&2
    return 1
  fi
  return 0
}

# rm_confirm "message" -> 0 to proceed. Auto-yes when REAL_ASSUME_YES=1.
rm_confirm() {
  local prompt="${1:-Proceed?}" reply
  if [[ "${REAL_ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  printf '%s [y/N] ' "$prompt" >&2
  read -r reply || return 1
  [[ "$reply" =~ ^[Yy]$ ]]
}
