#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day25/scripts"
  # stub kubectl: echoes its args; reports FAKE_CONTEXT for current-context
  STUB="$BATS_TEST_TMPDIR/kubectl"
  cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "config" ] && [ "$2" = "current-context" ]; then
  echo "${FAKE_CONTEXT:-dev-cluster}"
  exit 0
fi
echo "kubectl $*"
exit 0
EOF
  chmod +x "$STUB"
  export KUBECTL="$STUB"
  MANIFEST="$BATS_TEST_TMPDIR/app.yaml"
  echo "kind: ConfigMap" >"$MANIFEST"
}

@test "all day25 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

# ---- kubectl-lib ----
@test "is_protected_context flags prod-like, allows dev" {
  run bash -c "source '$S/kubectl-lib.sh'; is_protected_context prod-eu"
  assert_success
  run bash -c "source '$S/kubectl-lib.sh'; is_protected_context dev-cluster"
  assert_failure
}

@test "is_valid_namespace accepts good, rejects bad" {
  run bash -c "source '$S/kubectl-lib.sh'; is_valid_namespace web-1"
  assert_success
  run bash -c "source '$S/kubectl-lib.sh'; is_valid_namespace Bad_NS"
  assert_failure
}

# ---- k-apply ----
@test "k-apply is dry-run by default" {
  run bash "$S/k-apply.sh" --context staging --namespace web "$MANIFEST"
  assert_success
  assert_output_contains "apply -f"
  assert_output_contains "--dry-run=server"
  assert_output_contains "--context staging"
  assert_output_contains "--namespace web"
}

@test "k-apply --apply drops the dry-run flag" {
  run bash "$S/k-apply.sh" --context staging --namespace web --apply "$MANIFEST"
  assert_success
  assert_output_contains "apply -f"
  ! echo "$output" | grep -q -- "--dry-run=server"
}

@test "k-apply refuses a protected context without --confirm" {
  run bash "$S/k-apply.sh" --context prod-eu --namespace web --apply "$MANIFEST"
  assert_failure
  assert_output_contains "protected context"
}

@test "k-apply allows a protected context with --confirm" {
  run bash "$S/k-apply.sh" --context prod-eu --namespace web --apply --confirm "$MANIFEST"
  assert_success
  assert_output_contains "apply -f"
}

@test "k-apply requires context and namespace" {
  run bash "$S/k-apply.sh" "$MANIFEST"
  assert_failure
}

@test "k-apply rejects an invalid namespace" {
  run bash "$S/k-apply.sh" --context staging --namespace Bad_NS "$MANIFEST"
  assert_failure
}

@test "k-apply rejects a missing manifest" {
  run bash "$S/k-apply.sh" --context staging --namespace web "$BATS_TEST_TMPDIR/nope.yaml"
  assert_failure
}

# ---- context-guard ----
@test "context-guard passes on a matching context" {
  FAKE_CONTEXT=staging-cluster run bash "$S/context-guard.sh" staging-cluster
  assert_success
  assert_output_contains "context OK"
}

@test "context-guard fails on a mismatch" {
  FAKE_CONTEXT=prod-cluster run bash "$S/context-guard.sh" staging-cluster
  assert_failure
}

@test "context-guard with no arg shows usage" {
  run bash "$S/context-guard.sh"
  assert_failure
}
