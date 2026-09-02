#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day21/scripts"
  LOG="$BATS_TEST_TMPDIR/access.log"
  {
    echo '10.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET / HTTP/1.0" 200 100'
    echo '10.0.0.1 - - [10/Oct/2000:13:55:37 -0700] "GET /a HTTP/1.0" 200 150'
    echo '10.0.0.2 - - [10/Oct/2000:13:55:38 -0700] "POST /b HTTP/1.0" 404 50'
    echo '10.0.0.1 - - [10/Oct/2000:13:55:39 -0700] "GET / HTTP/1.0" 500 0'
    echo 'garbage line that is malformed'
  } >"$LOG"
}

@test "all day21 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

@test "analyzer reports correct totals and error rate" {
  run bash "$S/log-analyzer.sh" "$LOG"
  assert_success
  assert_output_contains "total requests:  4"
  assert_output_contains "malformed lines: 1"
  assert_output_contains "unique IPs:      2"
  assert_output_contains "errors (>=400):  2"
  assert_output_contains "error rate:      50.0%"
}

@test "analyzer computes total bytes" {
  run bash "$S/log-analyzer.sh" "$LOG"
  assert_success
  assert_output_contains "total bytes:     300"
}

@test "top IPs table ranks the busiest client first" {
  run bash "$S/log-analyzer.sh" -n 1 "$LOG"
  assert_success
  assert_output_contains "$(printf '3\t10.0.0.1')"
}

@test "status and method breakdowns appear" {
  run bash "$S/log-analyzer.sh" "$LOG"
  assert_success
  assert_output_contains "----- Status codes -----"
  assert_output_contains "$(printf '2\t200')"
  assert_output_contains "$(printf '3\tGET')"
}

@test "-o writes the report to a file" {
  out="$BATS_TEST_TMPDIR/report.txt"
  run bash "$S/log-analyzer.sh" -o "$out" "$LOG"
  assert_success
  [ -f "$out" ]
  grep -q "Log Analyzer Pro" "$out"
}

@test "analyzer rejects a missing file" {
  run bash "$S/log-analyzer.sh" "$BATS_TEST_TMPDIR/nope.log"
  assert_failure
}

@test "analyzer rejects a bad -n" {
  run bash "$S/log-analyzer.sh" -n abc "$LOG"
  assert_failure
}

@test "analyzer with no args shows usage and fails" {
  run bash "$S/log-analyzer.sh"
  assert_failure
}

@test "sample generator emits the requested line count in valid format" {
  run bash "$S/gen-sample-log.sh" 15
  assert_success
  [ "${#lines[@]}" -eq 15 ]
  # each line must parse: analyze it and expect zero malformed
  echo "$output" >"$BATS_TEST_TMPDIR/gen.log"
  run bash "$S/log-analyzer.sh" "$BATS_TEST_TMPDIR/gen.log"
  assert_success
  assert_output_contains "total requests:  15"
  assert_output_contains "malformed lines: 0"
}

@test "sample generator rejects a bad count" {
  run bash "$S/gen-sample-log.sh" abc
  assert_failure
}
