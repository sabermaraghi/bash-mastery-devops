#!/usr/bin/env bats
load ../../../tests/test_helper

# NOTE: the fake credentials below are assembled from fragments at runtime so no
# literal secret ever lives in this committed file — otherwise the repo's own
# gitleaks / detect-private-key hooks would (correctly) block the commit. The
# scanner under test still sees the fully-assembled string in the temp fixture.
setup() {
  S="$REPO_ROOT/days/day17/scripts"
  FAKE_AWS="AKIA""IOSFODNN7EXAMPLE"           # matches AKIA[0-9A-Z]{16}
  FAKE_PK="-----BEGIN RSA ""PRIVATE KEY-----" # matches the private-key header
}

@test "all day17 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

@test "security demo runs and denies malicious input" {
  run bash "$S/security-demo.sh"
  assert_success
  assert_output_contains "malicious environment correctly denied"
  assert_output_contains "path traversal correctly denied"
  assert_output_contains "injected action correctly denied"
}

@test "secret-scanner passes on a clean tree" {
  mkdir -p "$BATS_TEST_TMPDIR/clean"
  echo 'echo hello world' >"$BATS_TEST_TMPDIR/clean/ok.sh"
  run bash "$S/secret-scanner.sh" "$BATS_TEST_TMPDIR/clean"
  assert_success
  assert_output_contains "secret scan clean"
}

@test "secret-scanner catches an AWS key and a private key header" {
  d="$BATS_TEST_TMPDIR/dirty"
  mkdir -p "$d"
  echo "aws_key = $FAKE_AWS" >"$d/creds.txt"
  printf '%s\n' "$FAKE_PK" >"$d/id_rsa"
  run bash "$S/secret-scanner.sh" "$d"
  assert_failure
  assert_output_contains "AWS Access Key"
  assert_output_contains "Private Key"
}

@test "secret-scanner ignores .example template files" {
  d="$BATS_TEST_TMPDIR/tmpl"
  mkdir -p "$d"
  echo "api_key = $FAKE_AWS" >"$d/config.example"
  run bash "$S/secret-scanner.sh" "$d"
  assert_success
}

@test "harden-permissions writes a secret as 0600" {
  f="$BATS_TEST_TMPDIR/vault/secret.txt"
  run bash "$S/harden-permissions.sh" write "$f" "s3cr3t"
  assert_success
  [ "$(stat -c '%a' "$f")" = "600" ]
}

@test "harden-permissions audit flags a world-writable file" {
  d="$BATS_TEST_TMPDIR/aud"
  mkdir -p "$d"
  echo x >"$d/open.txt"
  chmod 666 "$d/open.txt"
  run bash "$S/harden-permissions.sh" audit "$d"
  assert_failure
  assert_output_contains "WORLD-WRITABLE"
}

@test "harden-permissions audit is clean on a locked-down tree" {
  d="$BATS_TEST_TMPDIR/safe"
  mkdir -p "$d"
  chmod 700 "$d"
  echo x >"$d/ok.txt"
  chmod 600 "$d/ok.txt"
  run bash "$S/harden-permissions.sh" audit "$d"
  assert_success
  assert_output_contains "permission audit clean"
}
