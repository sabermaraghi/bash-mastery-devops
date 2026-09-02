#!/usr/bin/env bats
# Day 18 Option 2 (real / cosign) tests. Tool-dependent cases skip when cosign
# is absent, so `bats -r days` stays green with or without cosign installed.
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day18/scripts"
}

@test "real-sign.sh is syntactically valid" {
  run bash -n "$S/real-sign.sh"
  assert_success
}

@test "real-sign rejects an unknown subcommand" {
  run bash "$S/real-sign.sh" bogus
  assert_failure
  assert_output_contains "usage:"
}

@test "real-sign --help exits 0 with usage" {
  run bash "$S/real-sign.sh" --help
  assert_success
  assert_output_contains "keygen"
}

@test "real-sign reports missing cosign when absent" {
  command -v cosign >/dev/null 2>&1 && skip "cosign is installed"
  run bash "$S/real-sign.sh" verify "$BATS_TEST_TMPDIR"
  [ "$status" -eq 3 ]
  assert_output_contains "missing required tool"
}

@test "keygen -> sign -> verify round-trips when cosign is present" {
  command -v cosign >/dev/null 2>&1 || skip "cosign not installed"
  export COSIGN_PASSWORD=""
  d="$BATS_TEST_TMPDIR/build"
  mkdir -p "$d"
  echo 'artifact one' >"$d/a.txt"
  echo 'artifact two' >"$d/b.txt"
  run bash "$S/real-sign.sh" keygen "$BATS_TEST_TMPDIR"
  assert_success
  export COSIGN_KEY="$BATS_TEST_TMPDIR/cosign.key" COSIGN_PUBKEY="$BATS_TEST_TMPDIR/cosign.pub"
  run bash "$S/real-sign.sh" sign "$d"
  assert_success
  run bash "$S/real-sign.sh" verify "$d"
  assert_success
  assert_output_contains "signature OK"
}

@test "verify FAILS on a tampered artifact when cosign is present" {
  command -v cosign >/dev/null 2>&1 || skip "cosign not installed"
  export COSIGN_PASSWORD=""
  d="$BATS_TEST_TMPDIR/build2"
  mkdir -p "$d"
  echo 'original' >"$d/a.txt"
  run bash "$S/real-sign.sh" keygen "$BATS_TEST_TMPDIR"
  assert_success
  export COSIGN_KEY="$BATS_TEST_TMPDIR/cosign.key" COSIGN_PUBKEY="$BATS_TEST_TMPDIR/cosign.pub"
  run bash "$S/real-sign.sh" sign "$d"
  assert_success
  # tamper AFTER signing: manifest no longer matches the tree's checksums
  echo 'tampered' >>"$d/a.txt"
  run bash "$REPO_ROOT/days/day18/scripts/verify-artifact.sh" verify "$d"
  assert_failure
}
