#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  DEMO="$REPO_ROOT/days/day09/scripts/json-demo.sh"
  PARSER="$REPO_ROOT/days/day09/scripts/json-log-parser.sh"
}

@test "scripts are syntactically valid" {
  run bash -n "$DEMO"
  assert_success
  run bash -n "$PARSER"
  assert_success
}

@test "json-demo runs (parses admins if jq present, else skips cleanly)" {
  run bash "$DEMO"
  assert_success
  if command -v jq >/dev/null 2>&1; then
    assert_output_contains "alice"
  else
    assert_output_contains "jq not installed"
  fi
}
