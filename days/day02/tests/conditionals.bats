#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  COND="$REPO_ROOT/days/day02/scripts/conditionals.sh"
  CHECK="$REPO_ROOT/days/day02/scripts/access-checker.sh"
}

@test "scripts are syntactically valid" {
  run bash -n "$COND"
  assert_success
  run bash -n "$CHECK"
  assert_success
}

@test "conditionals.sh classifies age 25 as adult" {
  run bash "$COND"
  assert_success
  assert_output_contains "You are an adult."
  assert_output_contains "Name is set: Bob"
}

@test "access-checker welcomes an adult" {
  run bash "$CHECK" Alice 25
  assert_success
  assert_output_contains "Welcome, Alice!"
}

@test "access-checker denies a minor" {
  run bash "$CHECK" Sam 15
  assert_success
  assert_output_contains "Access denied."
}

@test "access-checker rejects a non-numeric age" {
  run bash "$CHECK" Sam abc
  assert_failure
  assert_output_contains "must be a number"
}

@test "access-checker shows usage without two args" {
  run bash "$CHECK" only-one
  assert_failure
  assert_output_contains "Usage:"
}
