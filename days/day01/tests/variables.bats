#!/usr/bin/env bats
load ../../../tests/test_helper

setup() { SCRIPT="$REPO_ROOT/days/day01/scripts/variables.sh"; }

@test "variables.sh is syntactically valid" {
  run bash -n "$SCRIPT"
  assert_success
}

@test "variables.sh prints name, age and pi" {
  run bash "$SCRIPT"
  assert_success
  assert_output_contains "Name: Alice, Age: 30"
  assert_output_contains "Pi: 3.14"
}
