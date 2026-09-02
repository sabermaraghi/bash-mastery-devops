#!/usr/bin/env bash
# tests/test_helper.bash — shared BATS helper for every day.
# Load from a day suite with:  load ../../../tests/test_helper
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
export REPO_ROOT LIB_DIR="$REPO_ROOT/lib"

# Minimal assertions so suites don't depend on bats-assert being installed.
assert_success() { [ "$status" -eq 0 ] || {
  echo "expected success, got $status: $output"
  return 1
}; }
assert_failure() { [ "$status" -ne 0 ] || {
  echo "expected failure, got 0: $output"
  return 1
}; }
assert_output_contains() { [[ "$output" == *"$1"* ]] || {
  echo "output missing: $1"
  echo "got: $output"
  return 1
}; }
