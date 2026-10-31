#!/usr/bin/env bats
load ../../../tests/test_helper

setup() { SCRIPT="$REPO_ROOT/days/day03/scripts/loops.sh"; }

@test "loops.sh is syntactically valid" {
  run bash -n "$SCRIPT"
  assert_success
}

@test "loops.sh exercises for/while/until" {
  run bash "$SCRIPT"
  assert_success
  assert_output_contains "I like apple"
  assert_output_contains "Count: 5"
  assert_output_contains "While count: 3"
  assert_output_contains "Line: second line"
  assert_output_contains "Waiting... 2"
}
