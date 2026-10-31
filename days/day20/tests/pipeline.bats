#!/usr/bin/env bats
load ../../../tests/test_helper

setup() { S="$REPO_ROOT/days/day20/scripts"; }

@test "all day20 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

@test "field.sh extracts the requested column" {
  run bash -c "printf '%s\n' 'a b c' 'x y z' | bash '$S/field.sh' 2"
  assert_success
  assert_output_contains "b"
  assert_output_contains "y"
}

@test "field.sh skips lines missing the field" {
  run bash -c "printf '%s\n' 'one' 'has two' | bash '$S/field.sh' 2"
  assert_success
  [ "$output" = "two" ]
}

@test "field.sh rejects a bad field number" {
  run bash -c "echo hi | bash '$S/field.sh' 0"
  assert_failure
}

@test "histogram.sh counts and sorts most-frequent first" {
  run bash -c "printf '%s\n' a b a a b c | bash '$S/histogram.sh'"
  assert_success
  [ "${lines[0]}" = "$(printf '3\ta')" ]
  assert_output_contains "$(printf '2\tb')"
  assert_output_contains "$(printf '1\tc')"
}

@test "histogram.sh is silent on empty input" {
  run bash -c "printf '' | bash '$S/histogram.sh'"
  assert_success
  [ -z "$output" ]
}

@test "bar.sh renders bars for the largest count" {
  run bash -c "printf '%s\n' '$(printf '4\tapp')' '$(printf '1\tweb')' | bash '$S/bar.sh'"
  assert_success
  assert_output_contains "app"
  assert_output_contains "#"
}

@test "bar.sh is silent on empty input" {
  run bash -c "printf '' | bash '$S/bar.sh'"
  assert_success
  [ -z "$output" ]
}

@test "the three filters compose end to end" {
  run bash -c "printf '%s\n' '10.0.0.1 GET' '10.0.0.2 GET' '10.0.0.1 POST' | bash '$S/field.sh' 1 | bash '$S/histogram.sh' | bash '$S/bar.sh'"
  assert_success
  assert_output_contains "10.0.0.1"
  assert_output_contains "#"
}

@test "pipeline-demo runs end to end" {
  run bash "$S/pipeline-demo.sh"
  assert_success
  assert_output_contains "10.0.0.1"
}
