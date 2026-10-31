#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day26/scripts"
  STATE="$BATS_TEST_TMPDIR/cluster"
  CR="$BATS_TEST_TMPDIR/frontend.cr"
  {
    echo "kind = WidgetSet"
    echo "name = frontend"
    echo "replicas = 3"
    echo "image = nginx:1.25"
  } >"$CR"
}

set_replicas() { sed -i "s/^replicas = .*/replicas = $1/" "$CR"; }
set_image() { sed -i "s|^image = .*|image = $1|" "$CR"; }

@test "all day26 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

# ---- operator-lib ----
@test "cr_get reads spec fields" {
  run bash -c "source '$S/operator-lib.sh'; cr_get '$CR' replicas"
  assert_success
  assert_output_contains "3"
}

@test "is_uint accepts integers, rejects junk" {
  run bash -c "source '$S/operator-lib.sh'; is_uint 5"
  assert_success
  run bash -c "source '$S/operator-lib.sh'; is_uint 5x"
  assert_failure
}

# ---- reconcile ----
@test "reconcile creates the desired pods and a Ready status" {
  run bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE"
  assert_success
  assert_output_contains "CREATE frontend-0"
  assert_output_contains "3 created"
  [ -f "$STATE/pods/frontend-0" ]
  [ -f "$STATE/pods/frontend-2" ]
  run cat "$STATE/status/frontend.status"
  assert_output_contains "observedReplicas=3"
  assert_output_contains "phase=Ready"
}

@test "reconcile is idempotent" {
  bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE" >/dev/null
  run bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE"
  assert_success
  assert_output_contains "already reconciled"
}

@test "reconcile scales up" {
  bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE" >/dev/null
  set_replicas 5
  run bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE"
  assert_success
  assert_output_contains "CREATE frontend-3"
  assert_output_contains "CREATE frontend-4"
  [ -f "$STATE/pods/frontend-4" ]
}

@test "reconcile scales down and prunes extra pods" {
  set_replicas 5
  bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE" >/dev/null
  set_replicas 2
  run bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE"
  assert_success
  assert_output_contains "DELETE frontend-2"
  [ ! -f "$STATE/pods/frontend-4" ]
  [ -f "$STATE/pods/frontend-1" ]
}

@test "reconcile rolls out a new image" {
  bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE" >/dev/null
  set_image nginx:1.26
  run bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE"
  assert_success
  assert_output_contains "UPDATE frontend-0"
  [ "$(cat "$STATE/pods/frontend-0")" = "nginx:1.26" ]
}

@test "reconcile self-heals a deleted pod" {
  bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE" >/dev/null
  rm -f "$STATE/pods/frontend-1"
  run bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE"
  assert_success
  assert_output_contains "CREATE frontend-1"
  [ -f "$STATE/pods/frontend-1" ]
}

@test "reconcile --dry-run changes nothing" {
  run bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE" --dry-run
  assert_success
  assert_output_contains "planned"
  [ ! -d "$STATE/pods" ]
  [ ! -f "$STATE/status/frontend.status" ]
}

@test "reconcile rejects a non-integer replicas" {
  set_replicas abc
  run bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE"
  assert_failure
}

@test "reconcile rejects an unsupported kind" {
  sed -i "s/^kind = .*/kind = Mystery/" "$CR"
  run bash "$S/reconcile-cr.sh" --cr "$CR" --state-dir "$STATE"
  assert_failure
}

@test "reconcile rejects a missing CR file" {
  run bash "$S/reconcile-cr.sh" --cr "$BATS_TEST_TMPDIR/nope.cr" --state-dir "$STATE"
  assert_failure
}

# ---- control loop ----
@test "operator --once reconciles every CR in a dir" {
  CRD="$BATS_TEST_TMPDIR/manifests"
  mkdir -p "$CRD"
  cp "$CR" "$CRD/frontend.cr"
  {
    echo "kind = WidgetSet"
    echo "name = api"
    echo "replicas = 2"
    echo "image = api:v1"
  } >"$CRD/api.cr"
  run bash "$S/operator.sh" --cr-dir "$CRD" --state-dir "$STATE" --once
  assert_success
  [ -f "$STATE/pods/frontend-0" ]
  [ -f "$STATE/pods/api-1" ]
}

@test "operator --max-iterations bounds the loop" {
  CRD="$BATS_TEST_TMPDIR/manifests"
  mkdir -p "$CRD"
  cp "$CR" "$CRD/frontend.cr"
  run bash "$S/operator.sh" --cr-dir "$CRD" --state-dir "$STATE" --interval 0 --max-iterations 2
  assert_success
}

@test "operator rejects a missing cr-dir" {
  run bash "$S/operator.sh" --cr-dir "$BATS_TEST_TMPDIR/nope" --state-dir "$STATE" --once
  assert_failure
}
