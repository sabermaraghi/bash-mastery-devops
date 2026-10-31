#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  DEMO="$REPO_ROOT/days/day07/scripts/text-demo.sh"
  D="$REPO_ROOT/days/day07/scripts"
}

@test "all day-07 scripts are syntactically valid" {
  for s in "$D"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

@test "text-demo aggregates with grep/awk/cut/sed" {
  run bash "$DEMO"
  assert_success
  assert_output_contains "total: 1804"
  assert_output_contains "2 alice"
  assert_output_contains "alice,***,200"
}
