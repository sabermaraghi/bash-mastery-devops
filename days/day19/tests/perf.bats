#!/usr/bin/env bats
load ../../../tests/test_helper

setup() { S="$REPO_ROOT/days/day19/scripts"; }

@test "all day19 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

@test "bench.sh CLI runs and reports label + runs" {
  run bash "$S/bench.sh" 5 warmup true
  assert_success
  assert_output_contains "warmup"
  assert_output_contains "runs"
}

@test "bench.sh rejects a non-integer iteration count" {
  run bash "$S/bench.sh" abc label true
  assert_failure
}

@test "bench can be sourced and called on a function" {
  run bash -c "source '$S/bench.sh'; myfn() { :; }; bench 3 sourced myfn"
  assert_success
  assert_output_contains "sourced"
}

@test "optimize-demo runs end to end" {
  run bash "$S/optimize-demo.sh" 50
  assert_success
  assert_output_contains "uppercase"
  assert_output_contains "count lines"
}

@test "log-tally counts a field, sorted most-frequent first" {
  f="$BATS_TEST_TMPDIR/access.log"
  {
    echo "10.0.0.1 GET /"
    echo "10.0.0.2 GET /a"
    echo "10.0.0.1 GET /b"
    echo "10.0.0.1 POST /c"
    echo "10.0.0.2 GET /d"
  } >"$f"
  run bash "$S/log-tally.sh" "$f" 1
  assert_success
  # most frequent line first: 10.0.0.1 appears 3x
  [ "${lines[0]}" = "$(printf '3\t10.0.0.1')" ]
  assert_output_contains "10.0.0.2"
}

@test "log-tally honors the top_n limit" {
  f="$BATS_TEST_TMPDIR/a2.log"
  printf 'a x\nb y\nb z\nc q\n' >"$f"
  run bash "$S/log-tally.sh" "$f" 1 1
  assert_success
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "$(printf '2\tb')" ]
}

@test "log-tally rejects a bad field" {
  f="$BATS_TEST_TMPDIR/a3.log"
  echo "only one" >"$f"
  run bash "$S/log-tally.sh" "$f" 0
  assert_failure
}

@test "log-tally fails on a missing file" {
  run bash "$S/log-tally.sh" "$BATS_TEST_TMPDIR/nope.log" 1
  assert_failure
}
