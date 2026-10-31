#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  DEMO="$REPO_ROOT/days/day11/scripts/error-handling.sh"
  export LOG_FILE="$BATS_TEST_TMPDIR/test.log"
}

@test "all day-11 scripts are syntactically valid" {
  for s in "$REPO_ROOT"/days/day11/scripts/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

@test "error-handling demo logs, doubles, and traps" {
  run bash "$DEMO"
  assert_success
  assert_output_contains '"message":"risky(21) = 42"'
  assert_output_contains "rejected as expected"
  assert_output_contains "cleanup ran"
}
