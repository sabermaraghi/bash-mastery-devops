#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  export LOG_FILE="$BATS_TEST_TMPDIR/log"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/days/day14/scripts/backup-manager.sh"
  SRC="$BATS_TEST_TMPDIR/src"
  mkdir -p "$SRC"
  echo hi >"$SRC/f.txt"
}

@test "module is syntactically valid" {
  run bash -n "$REPO_ROOT/days/day14/scripts/backup-manager.sh"
  assert_success
}

@test "backup() creates an archive using shared lib helpers" {
  run backup "$SRC" "$BATS_TEST_TMPDIR/out"
  assert_success
  [ -n "$(find "$BATS_TEST_TMPDIR/out" -name '*.tar.gz')" ]
}

@test "backup() rejects an unsafe path via the shared validator" {
  run backup "../etc" "$BATS_TEST_TMPDIR/out"
  assert_failure
}
