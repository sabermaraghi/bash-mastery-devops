#!/usr/bin/env bats
load ../../../tests/test_helper

setup() { S="$REPO_ROOT/days/day23/scripts"; }

@test "all day23 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

# ---- pipeline-lib.sh ----
@test "run_stage records a pass and pipeline_summary succeeds" {
  run bash -c "source '$S/pipeline-lib.sh'; run_stage ok true; pipeline_summary"
  assert_success
  assert_output_contains "1 passed, 0 failed"
}

@test "run_stage records a failure and pipeline_summary fails" {
  run bash -c "source '$S/pipeline-lib.sh'; run_stage bad false || true; pipeline_summary"
  assert_failure
  assert_output_contains "0 passed, 1 failed"
}

# ---- ci-run.sh (good pipeline) ----
@test "ci-run runs a passing pipeline to completion" {
  f="$BATS_TEST_TMPDIR/good.ci"
  {
    echo "# comment"
    echo "lint = true"
    echo "test = echo hi"
    echo ""
    echo "build = true"
  } >"$f"
  run bash "$S/ci-run.sh" "$f"
  assert_success
  assert_output_contains "3 passed, 0 failed"
}

# ---- fail-fast vs keep-going ----
@test "ci-run is fail-fast by default (stops after first failure)" {
  f="$BATS_TEST_TMPDIR/ff.ci"
  {
    echo "a = true"
    echo "b = false"
    echo "c = true"
  } >"$f"
  run bash "$S/ci-run.sh" "$f"
  assert_failure
  # c must NOT run -> exactly 1 passed, 1 failed
  assert_output_contains "1 passed, 1 failed"
}

@test "ci-run --keep-going runs every stage" {
  f="$BATS_TEST_TMPDIR/kg.ci"
  {
    echo "a = true"
    echo "b = false"
    echo "c = true"
  } >"$f"
  run bash "$S/ci-run.sh" --keep-going "$f"
  assert_failure
  assert_output_contains "2 passed, 1 failed"
}

@test "ci-run --file flag works" {
  f="$BATS_TEST_TMPDIR/flag.ci"
  echo "only = true" >"$f"
  run bash "$S/ci-run.sh" --file "$f"
  assert_success
  assert_output_contains "1 passed, 0 failed"
}

@test "ci-run fails on a missing file" {
  run bash "$S/ci-run.sh" "$BATS_TEST_TMPDIR/nope.ci"
  assert_failure
}

@test "ci-run fails when the pipeline has no runnable stages" {
  f="$BATS_TEST_TMPDIR/empty.ci"
  {
    echo "# just a comment"
    echo ""
  } >"$f"
  run bash "$S/ci-run.sh" "$f"
  assert_failure
}

@test "ci-run with no argument shows usage" {
  run bash "$S/ci-run.sh"
  assert_failure
}

@test "the bundled example pipeline passes" {
  run bash "$S/ci-run.sh" "$REPO_ROOT/days/day23/examples/pipeline.ci"
  assert_success
  assert_output_contains "4 passed, 0 failed"
}
