#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  ARGS="$REPO_ROOT/days/day05/scripts/arguments.sh"
  GETOPTS="$REPO_ROOT/days/day05/scripts/args-getopts.sh"
  BACKUP="$REPO_ROOT/days/day05/scripts/backup.sh"
  TMP="$(mktemp -d)"
}
teardown() { rm -rf "$TMP"; }

@test "all scripts are syntactically valid" {
  run bash -n "$ARGS"
  assert_success
  run bash -n "$GETOPTS"
  assert_success
  run bash -n "$BACKUP"
  assert_success
}

@test "arguments.sh reports count and echoes args" {
  run bash "$ARGS" alpha beta
  assert_success
  assert_output_contains "Arg count   : 2"
  assert_output_contains "arg[2] = beta"
}

@test "getopts parses -e and -v" {
  run bash "$GETOPTS" -e prod -v
  assert_success
  assert_output_contains "Environment: prod"
  assert_output_contains "Verbose mode is ON"
}

@test "getopts -h prints usage" {
  run bash "$GETOPTS" -h
  assert_success
  assert_output_contains "Usage:"
}

@test "getopts rejects an unknown flag" {
  run bash "$GETOPTS" -z
  assert_failure
  assert_output_contains "Unknown option"
}

@test "backup.sh archives a real directory" {
  mkdir -p "$TMP/data" && echo hi >"$TMP/data/file.txt"
  run bash "$BACKUP" "$TMP/data" "$TMP/out"
  assert_success
  assert_output_contains "Created archive:"
  [ -n "$(find "$TMP/out" -name '*.tar.gz')" ]
}

@test "backup.sh fails on a missing source" {
  run bash "$BACKUP" "$TMP/does-not-exist"
  assert_failure
  assert_output_contains "Source directory not found"
}
