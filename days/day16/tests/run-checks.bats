#!/usr/bin/env bats
load ../../../tests/test_helper

setup() { CHK="$REPO_ROOT/days/day16/scripts/run-checks.sh"; }

@test "run-checks.sh is syntactically valid" {
  run bash -n "$CHK"
  assert_success
}

@test "run-checks runs the syntax gate over every repo script" {
  # We assert the gate RAN and the syntax stage passed. We deliberately do NOT
  # require overall success: installed optional tools (gitleaks/trivy) may flag
  # real issues in a user's own environment, which is the tool working, not a
  # test failure.
  run bash "$CHK"
  assert_output_contains "syntax (bash -n)"
  assert_output_contains "checked"
  # the syntax stage itself must never report a failure
  [[ "$output" != *"SYNTAX FAIL"* ]]
}
