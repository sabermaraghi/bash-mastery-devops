#!/usr/bin/env bats
load ../../../tests/test_helper

# Fake credential assembled at runtime so no literal secret sits in this file
# (the repo's gitleaks / detect-private-key hooks would block it otherwise).
setup() {
  S="$REPO_ROOT/days/day18/scripts"
  FAKE_AWS="AKIA""IOSFODNN7EXAMPLE"
}

@test "all day18 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

@test "pipeline --list prints the ordered stages" {
  run bash "$S/zero-trust-pipeline.sh" --list
  assert_success
  assert_output_contains "syntax"
  assert_output_contains "secrets"
  assert_output_contains "integrity"
}

@test "verify-artifact: manifest then verify succeeds" {
  d="$BATS_TEST_TMPDIR/art"
  mkdir -p "$d/sub"
  echo 'hello' >"$d/a.txt"
  echo 'world' >"$d/sub/b.txt"
  run bash "$S/verify-artifact.sh" manifest "$d"
  assert_success
  run bash "$S/verify-artifact.sh" verify "$d"
  assert_success
  assert_output_contains "integrity OK"
}

@test "verify-artifact: tampering is detected" {
  d="$BATS_TEST_TMPDIR/art2"
  mkdir -p "$d"
  echo 'original' >"$d/a.txt"
  bash "$S/verify-artifact.sh" manifest "$d"
  echo 'tampered' >"$d/a.txt"
  run bash "$S/verify-artifact.sh" verify "$d"
  assert_failure
}

@test "pipeline passes on a clean, verified tree" {
  d="$BATS_TEST_TMPDIR/clean"
  mkdir -p "$d"
  echo 'echo ok' >"$d/run.sh"
  bash "$S/verify-artifact.sh" manifest "$d"
  run bash "$S/zero-trust-pipeline.sh" "$d"
  assert_success
  assert_output_contains "pipeline PASSED"
}

@test "pipeline fails closed on a hardcoded secret" {
  d="$BATS_TEST_TMPDIR/leaky"
  mkdir -p "$d"
  echo "key = $FAKE_AWS" >"$d/config.txt"
  run bash "$S/zero-trust-pipeline.sh" "$d"
  assert_failure
  assert_output_contains "secrets"
}

@test "pipeline fails closed on a syntax error" {
  d="$BATS_TEST_TMPDIR/broken"
  mkdir -p "$d"
  printf 'if then fi\n' >"$d/bad.sh"
  run bash "$S/zero-trust-pipeline.sh" "$d"
  assert_failure
}

@test "deploy-guard authorizes when all preconditions pass" {
  d="$BATS_TEST_TMPDIR/dep"
  mkdir -p "$d"
  echo 'artifact' >"$d/app.bin"
  bash "$S/verify-artifact.sh" manifest "$d"
  run env DEPLOY_ENV=staging TARGET_HOST=web-01 ALLOWED_HOSTS=web-01,web-02 ARTIFACT_DIR="$d" bash "$S/deploy-guard.sh"
  assert_success
  assert_output_contains "DEPLOY AUTHORIZED"
}

@test "deploy-guard blocks an off-allowlist host" {
  d="$BATS_TEST_TMPDIR/dep2"
  mkdir -p "$d"
  echo 'artifact' >"$d/app.bin"
  bash "$S/verify-artifact.sh" manifest "$d"
  run env DEPLOY_ENV=prod TARGET_HOST=evil-host ALLOWED_HOSTS=web-01 ARTIFACT_DIR="$d" bash "$S/deploy-guard.sh"
  assert_failure
}

@test "deploy-guard blocks a tampered artifact" {
  d="$BATS_TEST_TMPDIR/dep3"
  mkdir -p "$d"
  echo 'artifact' >"$d/app.bin"
  bash "$S/verify-artifact.sh" manifest "$d"
  echo 'tampered' >"$d/app.bin"
  run env DEPLOY_ENV=staging TARGET_HOST=web-01 ALLOWED_HOSTS=web-01 ARTIFACT_DIR="$d" bash "$S/deploy-guard.sh"
  assert_failure
}
