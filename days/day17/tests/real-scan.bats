#!/usr/bin/env bats
# Option 2 (real) tests. Tool-dependent cases skip when the tool is absent, so
# `bats -r days` stays green with or without gitleaks/trivy installed.
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day17/scripts"
  RM="$REPO_ROOT/platform/lib/realmode.sh"
}

@test "real-scan.sh is syntactically valid" {
  run bash -n "$S/real-scan.sh"
  assert_success
}

@test "realmode.sh is syntactically valid" {
  run bash -n "$RM"
  assert_success
}

@test "rm_require_tools fails and hints when a tool is missing" {
  run bash -c "source '$RM'; rm_require_tools definitely-not-a-real-tool-xyz"
  assert_failure
  assert_output_contains "missing required tool"
}

@test "rm_banner announces REAL MODE" {
  run bash -c "source '$RM'; rm_banner 'unit test'"
  assert_success
  assert_output_contains "REAL MODE"
}

@test "rm_confirm auto-approves when REAL_ASSUME_YES=1" {
  run bash -c "source '$RM'; REAL_ASSUME_YES=1 rm_confirm 'go?'"
  assert_success
}

@test "real-scan rejects an unknown argument" {
  run bash "$S/real-scan.sh" --bogus
  assert_failure
  assert_output_contains "unknown arg"
}

@test "real-scan accepts --no-git (not an unknown arg)" {
  run bash "$S/real-scan.sh" --dir "$REPO_ROOT" --secrets-only --no-git
  # exits 0/1 (scanned) or 3 (gitleaks missing), never 2 (usage)
  [ "$status" -ne 2 ]
  [[ "$output" != *"unknown arg"* ]]
}

@test "real-scan errors on a non-existent directory" {
  run bash "$S/real-scan.sh" --dir "$BATS_TEST_TMPDIR/nope" --secrets-only
  assert_failure
}

@test "real-scan reports missing tools when gitleaks is absent" {
  command -v gitleaks >/dev/null 2>&1 && skip "gitleaks is installed"
  run bash "$S/real-scan.sh" --dir "$REPO_ROOT" --secrets-only
  [ "$status" -eq 3 ]
  assert_output_contains "missing required tool"
}

@test "real-scan --no-git runs a clean working-tree scan when gitleaks is present" {
  command -v gitleaks >/dev/null 2>&1 || skip "gitleaks not installed"
  d="$BATS_TEST_TMPDIR/clean"
  mkdir -p "$d"
  echo 'echo hello world' >"$d/ok.sh"
  run bash "$S/real-scan.sh" --dir "$d" --secrets-only --no-git
  assert_success
  assert_output_contains "real scan clean"
}
