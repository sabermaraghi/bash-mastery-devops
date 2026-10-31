#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  # shellcheck source=/dev/null
  source "$REPO_ROOT/days/day15/scripts/calc.sh"
}

@test "add sums two numbers" {
  run add 2 3
  assert_success
  [ "$output" -eq 5 ]
}

@test "divide performs integer division" {
  run divide 10 2
  assert_success
  [ "$output" -eq 5 ]
}

@test "divide by zero fails with a message" {
  run divide 1 0
  assert_failure
  assert_output_contains "division by zero"
}

@test "calc.sh is runnable from the CLI" {
  run bash "$REPO_ROOT/days/day15/scripts/calc.sh" add 4 5
  assert_success
  [ "$output" -eq 9 ]
}
