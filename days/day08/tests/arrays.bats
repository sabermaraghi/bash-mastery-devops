#!/usr/bin/env bats
load ../../../tests/test_helper

setup() { SCRIPT="$REPO_ROOT/days/day08/scripts/arrays.sh"; }

@test "arrays.sh is syntactically valid" {
  run bash -n "$SCRIPT"
  assert_success
}

@test "arrays.sh handles indexed, associative, and mapfile" {
  run bash "$SCRIPT"
  assert_success
  assert_output_contains "Server count: 4"
  assert_output_contains "Last: cache01"
  assert_output_contains "https port is 443"
  assert_output_contains "Read 3 lines; second is two"
}
