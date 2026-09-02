#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day24/scripts"
  DESIRED="$BATS_TEST_TMPDIR/desired"
  LIVE="$BATS_TEST_TMPDIR/live"
  mkdir -p "$DESIRED/app"
  echo "deploy-v1" >"$DESIRED/app/deployment.yaml"
  echo "svc-v1" >"$DESIRED/app/service.yaml"
}

@test "all day24 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

# ---- gitops-lib ----
@test "diff_state reports MISSING for undeployed files" {
  mkdir -p "$LIVE"
  run bash -c "source '$S/gitops-lib.sh'; diff_state '$DESIRED' '$LIVE'"
  assert_success
  assert_output_contains "MISSING"
  assert_output_contains "app/deployment.yaml"
}

# ---- reconcile ----
@test "reconcile creates missing files and makes live match" {
  run bash "$S/reconcile.sh" "$DESIRED" "$LIVE"
  assert_success
  assert_output_contains "CREATE"
  assert_output_contains "2 created"
  [ -f "$LIVE/app/deployment.yaml" ]
  [ "$(cat "$LIVE/app/service.yaml")" = "svc-v1" ]
}

@test "reconcile is idempotent (second run is a no-op)" {
  bash "$S/reconcile.sh" "$DESIRED" "$LIVE" >/dev/null
  run bash "$S/reconcile.sh" "$DESIRED" "$LIVE"
  assert_success
  assert_output_contains "already in sync"
}

@test "reconcile --dry-run does not modify live" {
  mkdir -p "$LIVE"
  run bash "$S/reconcile.sh" --dry-run "$DESIRED" "$LIVE"
  assert_success
  assert_output_contains "planned"
  [ ! -f "$LIVE/app/deployment.yaml" ]
}

@test "reconcile updates a drifted file" {
  bash "$S/reconcile.sh" "$DESIRED" "$LIVE" >/dev/null
  echo "svc-v2" >"$DESIRED/app/service.yaml"
  run bash "$S/reconcile.sh" "$DESIRED" "$LIVE"
  assert_success
  assert_output_contains "UPDATE"
  [ "$(cat "$LIVE/app/service.yaml")" = "svc-v2" ]
}

@test "reconcile --prune removes undeclared files; default keeps them" {
  bash "$S/reconcile.sh" "$DESIRED" "$LIVE" >/dev/null
  echo "rogue" >"$LIVE/app/rogue.yaml"
  # default: ignored, file stays
  run bash "$S/reconcile.sh" "$DESIRED" "$LIVE"
  assert_output_contains "IGNORE"
  [ -f "$LIVE/app/rogue.yaml" ]
  # with --prune: removed
  run bash "$S/reconcile.sh" --prune "$DESIRED" "$LIVE"
  assert_success
  assert_output_contains "PRUNE"
  [ ! -f "$LIVE/app/rogue.yaml" ]
}

@test "reconcile rejects a missing desired dir" {
  run bash "$S/reconcile.sh" "$BATS_TEST_TMPDIR/nope" "$LIVE"
  assert_failure
}

@test "reconcile with wrong arg count shows usage" {
  run bash "$S/reconcile.sh" "$DESIRED"
  assert_failure
}

# ---- drift-detect ----
@test "drift-detect reports no drift after reconcile" {
  bash "$S/reconcile.sh" --prune "$DESIRED" "$LIVE" >/dev/null
  run bash "$S/drift-detect.sh" "$DESIRED" "$LIVE"
  assert_success
  assert_output_contains "no drift"
}

@test "drift-detect exits non-zero and lists divergence" {
  bash "$S/reconcile.sh" --prune "$DESIRED" "$LIVE" >/dev/null
  echo "tampered" >"$LIVE/app/service.yaml"
  echo "rogue" >"$LIVE/app/rogue.yaml"
  run bash "$S/drift-detect.sh" "$DESIRED" "$LIVE"
  assert_failure
  assert_output_contains "CHANGED"
  assert_output_contains "EXTRA"
  assert_output_contains "drift detected"
}

@test "drift-detect rejects a missing dir" {
  run bash "$S/drift-detect.sh" "$DESIRED" "$BATS_TEST_TMPDIR/nope"
  assert_failure
}
