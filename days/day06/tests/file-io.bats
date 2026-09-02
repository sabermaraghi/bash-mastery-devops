#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  IO="$REPO_ROOT/days/day06/scripts/file-io.sh"
  FIND="$REPO_ROOT/days/day06/scripts/find-large-files.sh"
}

@test "scripts are syntactically valid" {
  run bash -n "$IO"
  assert_success
  run bash -n "$FIND"
  assert_success
}

@test "file-io.sh writes, appends, and reads back four lines" {
  run bash "$IO"
  assert_success
  assert_output_contains "read[4]: line four"
  assert_output_contains "Total lines: 4"
}
