#!/usr/bin/env bash
# real-ci.sh — Day 23, Option 2 (REAL): run an actual CI pipeline against THIS
# git repository, instead of the offline text-file demo.
#
# It COMPOSES the Day 23 engine (pipeline-lib.sh: run_stage / pipeline_summary)
# rather than replacing it, and adds the things a real CI needs:
#   • operates on a real git repo (scoped to your changed shell files by default,
#     or the whole tree with --all, or a diff vs a base ref with --base REF)
#   • real stages: lint (shellcheck, else bash -n), test (bats), secrets (gitleaks)
#   • degrades gracefully: a missing tool SKIPS its stage with a warning — it is
#     never a fake pass, and never a hard failure
#   • speaks GitHub Actions: under $GITHUB_ACTIONS it emits ::group:: / ::error::
#     annotations so the same script works locally and in a real workflow
#
# Usage:
#   bash real-ci.sh [--all] [--base REF] [--keep-going]
#     (default)      lint/test/secrets on shell files changed vs HEAD
#     --all          run against every tracked shell file
#     --base REF     run against files changed since REF (e.g. origin/main)
#     --keep-going   run every stage even after a failure (default: fail-fast)
#
# Exit: 0 all stages passed/skipped · 1 a stage failed or not a git repo · 2 usage
#       · 3 git not installed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day23-real-ci.log}" COMPONENT="real-ci"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/pipeline-lib.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/platform/lib/realmode.sh"

usage() {
  echo "usage: $0 [--all] [--base REF] [--repo DIR] [--keep-going]" >&2
  exit 2
}

# ---- GitHub Actions annotation helpers (no-ops outside CI) ----
_gha() { [[ "${GITHUB_ACTIONS:-}" == "true" ]]; }
_gha_group() { _gha && printf '::group::%s\n' "$1" || true; }
_gha_endgroup() { _gha && printf '::endgroup::\n' || true; }
_gha_error() { _gha && printf '::error::%s\n' "$1" || true; }

# Syntax fallback when shellcheck is absent: bash -n every file, fail if any fail.
_syntax_check() {
  local f rc=0
  for f in "$@"; do
    bash -n "$f" || rc=1
  done
  return "$rc"
}

KEEP_GOING=0

# run one CI stage inside a GitHub Actions group, annotate on failure, and
# honor fail-fast/keep-going. Returns the stage rc.
ci_stage() {
  local name="$1"
  shift
  local rc=0
  _gha_group "$name"
  run_stage "$name" "$@" || rc=$?
  _gha_endgroup
  if ((rc != 0)); then
    _gha_error "stage '$name' failed (rc=$rc)"
  fi
  return "$rc"
}

main() {
  # NB: REPO_ROOT is where THIS script + its libs live. The repo we SCAN is
  # separate (defaults to REPO_ROOT) so it can be pointed elsewhere via --repo.
  local scope="changed" base="" target="$REPO_ROOT"
  while (($#)); do
    case "$1" in
      --all) scope="all" ;;
      --base)
        base="${2:?--base needs a ref}"
        scope="base"
        shift
        ;;
      --repo)
        target="${2:?--repo needs a directory}"
        shift
        ;;
      --keep-going) KEEP_GOING=1 ;;
      -h | --help) usage ;;
      *)
        echo "unknown argument: $1" >&2
        usage
        ;;
    esac
    shift
  done

  rm_require_tools git || return 3
  git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    log_error "not a git repository: $target"
    return 1
  }

  rm_banner "Day 23 — real CI pipeline (git-scoped: lint / test / secrets)"

  # ---- collect the shell files in scope ----
  # NB: capture into a string then split with a here-string; this repo's target
  # shells don't support process substitution (< <(...)).
  local listing=""
  case "$scope" in
    all)
      log_info "scope: all tracked shell files"
      listing="$(git -C "$target" ls-files '*.sh')"
      ;;
    base)
      log_info "scope: shell files changed since $base"
      listing="$(git -C "$target" diff --name-only --diff-filter=ACMR "$base" -- '*.sh')"
      ;;
    *)
      log_info "scope: shell files changed vs HEAD (staged + unstaged)"
      listing="$(
        {
          git -C "$target" diff --name-only --diff-filter=ACMR HEAD -- '*.sh'
          git -C "$target" ls-files --others --exclude-standard '*.sh'
        } | sort -u
      )"
      ;;
  esac
  # keep only paths that still exist, and make them absolute
  local -a sh=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" && -f "$target/$line" ]] && sh+=("$target/$line")
  done <<<"$listing"

  local fail=0

  # ---- stage: lint ----
  if ((${#sh[@]} == 0)); then
    log_warn "no shell files in scope — skipping lint"
  elif command -v shellcheck >/dev/null 2>&1; then
    ci_stage lint shellcheck --severity=error "${sh[@]}" || fail=1
  else
    log_warn "shellcheck not installed — falling back to 'bash -n' syntax check"
    rm_install_hint shellcheck >&2
    ci_stage lint _syntax_check "${sh[@]}" || fail=1
  fi
  if ((fail && KEEP_GOING == 0)); then
    log_error "fail-fast: stopping after lint"
    pipeline_summary || true
    return 1
  fi

  # ---- stage: test ----
  if [[ -d "$target/days" ]] && command -v bats >/dev/null 2>&1; then
    ci_stage test bats -r "$target/days" || fail=1
  else
    log_warn "bats not installed (or no tests) — skipping test stage"
    command -v bats >/dev/null 2>&1 || rm_install_hint bats >&2
  fi
  if ((fail && KEEP_GOING == 0)); then
    log_error "fail-fast: stopping after test"
    pipeline_summary || true
    return 1
  fi

  # ---- stage: secrets ----
  # --no-git: scan the current working tree only, NOT git history. New secrets
  # about to be committed are caught; already-purged/old history commits are not
  # re-flagged forever (matches the Day 17 policy).
  if command -v gitleaks >/dev/null 2>&1; then
    ci_stage secrets gitleaks detect --source "$target" --no-git --no-banner --redact || fail=1
  else
    log_warn "gitleaks not installed — skipping secret scan"
    rm_install_hint gitleaks >&2
  fi

  # ---- report ----
  pipeline_summary || fail=1
  return "$fail"
}

main "$@"
