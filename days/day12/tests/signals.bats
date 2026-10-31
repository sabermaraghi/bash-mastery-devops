#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  DEMO="$REPO_ROOT/days/day12/scripts/signals-demo.sh"
  MON="$REPO_ROOT/days/day12/scripts/monitor.sh"
}

@test "scripts are syntactically valid" {
  run bash -n "$DEMO"
  assert_success
  run bash -n "$MON"
  assert_success
}

@test "signals-demo runs background jobs and waits" {
  run bash "$DEMO"
  assert_success
  assert_output_contains "started PIDs:"
  assert_output_contains "worker(0.1) finished"
  assert_output_contains "all workers done"
}
