#!/usr/bin/env bash
# ci-run.sh — execute a pipeline defined in a simple text file.
#
# Pipeline file format (one stage per line):
#   name = shell command to run
#   # lines starting with '#' and blank lines are ignored
#
# Stages run top-to-bottom. By default the pipeline is FAIL-FAST: the first
# failing stage stops the run. Pass --keep-going to run every stage regardless.
#
# Usage:
#   bash ci-run.sh [--keep-going] --file PIPELINE
#   bash ci-run.sh [--keep-going] PIPELINE
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export LOG_FILE="${LOG_FILE:-/tmp/day23-ci.log}" COMPONENT="ci-run"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/validator.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/pipeline-lib.sh"

usage() {
  echo "usage: $0 [--keep-going] [--file] PIPELINE" >&2
  exit 2
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

main() {
  local keep_going=0 file=""
  while (($#)); do
    case "$1" in
      --keep-going) keep_going=1 ;;
      --file)
        file="${2:?}"
        shift
        ;;
      -h | --help) usage ;;
      -*)
        echo "unknown flag: $1" >&2
        usage
        ;;
      *) [[ -z "$file" ]] && file="$1" || usage ;;
    esac
    shift
  done

  [[ -n "$file" ]] || usage
  require_file "$file" || return 1

  local line name cmd stages=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || {
      log_warn "skipping malformed line (no '='): $line"
      continue
    }
    name="$(trim "${line%%=*}")"
    cmd="$(trim "${line#*=}")"
    [[ -n "$name" && -n "$cmd" ]] || {
      log_warn "skipping incomplete stage: $line"
      continue
    }
    stages=$((stages + 1))
    if ! run_stage "$name" bash -c "$cmd"; then
      if ((keep_going == 0)); then
        log_error "stage '$name' failed — stopping (fail-fast)"
        break
      fi
      log_warn "stage '$name' failed — continuing (--keep-going)"
    fi
  done <"$file"

  ((stages > 0)) || {
    log_error "no runnable stages found in $file"
    return 1
  }

  pipeline_summary
}

main "$@"
