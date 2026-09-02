#!/usr/bin/env bats
# Tests for the REAL Day 23 CI pipeline (real-ci.sh).
# Tool-independent checks always run; the lint stage falls back to `bash -n`
# when shellcheck is absent, so the happy path is exercised everywhere.
# We point the runner at a throwaway repo with --repo so tests are hermetic.
load ../../../tests/test_helper

setup() {
  SCRIPT="$REPO_ROOT/days/day23/scripts/real-ci.sh"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email ci@example.com
  git -C "$REPO" config user.name ci
}

@test "real-ci.sh is syntactically valid" {
  run bash -n "$SCRIPT"
  assert_success
}

@test "unknown argument shows usage (exit 2)" {
  run bash "$SCRIPT" --bogus
  assert_failure 2
}

@test "--help shows usage (exit 2)" {
  run bash "$SCRIPT" --help
  assert_failure 2
}

@test "non-git directory -> exit 1" {
  run bash "$SCRIPT" --all --repo "$BATS_TEST_TMPDIR/not-a-repo"
  assert_failure 1
  assert_output_contains "not a git repository"
}

@test "clean repo with a valid script passes (bash -n fallback)" {
  cat >"$REPO/ok.sh" <<'EOF'
#!/usr/bin/env bash
echo ok
EOF
  git -C "$REPO" add ok.sh
  git -C "$REPO" commit -qm init
  run bash "$SCRIPT" --all --repo "$REPO"
  assert_success
  assert_output_contains "passed"
}

@test "a broken script fails the lint stage (fail-fast, non-zero)" {
  printf '#!/usr/bin/env bash\necho "unterminated\n' >"$REPO/bad.sh"
  git -C "$REPO" add bad.sh
  git -C "$REPO" commit -qm bad
  run bash "$SCRIPT" --all --repo "$REPO"
  assert_failure
}

@test "emits GitHub Actions annotations under GITHUB_ACTIONS" {
  printf '#!/usr/bin/env bash\necho "unterminated\n' >"$REPO/bad.sh"
  git -C "$REPO" add bad.sh
  git -C "$REPO" commit -qm bad
  run env GITHUB_ACTIONS=true bash "$SCRIPT" --all --repo "$REPO"
  assert_failure
  assert_output_contains "::error::"
}

@test "gitleaks stage runs when the tool is present (simulated)" {
  fake="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fake"
  printf '#!/usr/bin/env bash\necho "leaks: 0"\nexit 0\n' >"$fake/gitleaks"
  chmod +x "$fake/gitleaks"
  cat >"$REPO/ok.sh" <<'EOF'
#!/usr/bin/env bash
echo ok
EOF
  git -C "$REPO" add ok.sh
  git -C "$REPO" commit -qm init
  run env PATH="$fake:$PATH" bash "$SCRIPT" --all --repo "$REPO"
  assert_success
  assert_output_contains "secrets"
}
