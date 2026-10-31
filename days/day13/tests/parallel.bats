#!/usr/bin/env bats
load ../../../tests/test_helper

setup() { DEMO="$REPO_ROOT/days/day13/scripts/parallel-demo.sh"; }

@test "all day-13 scripts are syntactically valid" {
  for s in "$REPO_ROOT"/days/day13/scripts/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

@test "parallel-demo processes every item with a bounded pool" {
  run bash "$DEMO"
  assert_success
  assert_output_contains "Processed 6 items concurrently"
  assert_output_contains "processed:foxtrot"
}
