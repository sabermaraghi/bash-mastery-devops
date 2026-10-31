#!/usr/bin/env bats
load ../../../tests/test_helper

setup() { SCRIPT="$REPO_ROOT/days/day04/scripts/functions.sh"; }

@test "functions.sh is syntactically valid" {
  run bash -n "$SCRIPT"
  assert_success
}

@test "functions.sh greets, adds, and collects info" {
  run bash "$SCRIPT"
  assert_success
  assert_output_contains "Hello, DevOps Engineer!"
  assert_output_contains "15 + 27 = 42"
  assert_output_contains "Backing up /etc -> /var/backup"
  assert_output_contains "System info collected:"
}
