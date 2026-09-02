#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day27/scripts"
  BASE="$BATS_TEST_TMPDIR/base"
  mkdir -p "$BASE/src/frontend" "$BASE/src/api" "$BASE/apps"
  echo "fe-v1" >"$BASE/src/frontend/deploy.yaml"
  echo "api-v1" >"$BASE/src/api/deploy.yaml"
  # leaf apps
  {
    echo "kind = Application"
    echo "name = frontend"
    echo "source = src/frontend"
    echo "dest = live/frontend"
  } >"$BASE/apps/frontend.app"
  {
    echo "kind = Application"
    echo "name = api"
    echo "source = src/api"
    echo "dest = live/api"
  } >"$BASE/apps/api.app"
  # root app-of-apps
  {
    echo "kind = Application"
    echo "name = platform-root"
    echo "apps = apps"
  } >"$BASE/root.app"
}

@test "all day27 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

# ---- argo-lib ----
@test "app_get reads manifest fields" {
  run bash -c "source '$S/argo-lib.sh'; app_get '$BASE/apps/frontend.app' name"
  assert_success
  assert_output_contains "frontend"
}

# ---- sync-app ----
@test "sync-app creates dest files and reports Synced/Healthy" {
  run bash "$S/sync-app.sh" --app "$BASE/apps/frontend.app" --base "$BASE"
  assert_success
  assert_output_contains "CREATE"
  assert_output_contains "app frontend: Synced (Healthy)"
  [ "$(cat "$BASE/live/frontend/deploy.yaml")" = "fe-v1" ]
}

@test "sync-app is idempotent (Synced, no actions)" {
  bash "$S/sync-app.sh" --app "$BASE/apps/frontend.app" --base "$BASE" >/dev/null
  run bash "$S/sync-app.sh" --app "$BASE/apps/frontend.app" --base "$BASE"
  assert_success
  assert_output_contains "Synced"
  ! echo "$output" | grep -q "CREATE"
}

@test "sync-app --dry-run reports OutOfSync and exits 3, changing nothing" {
  run bash "$S/sync-app.sh" --app "$BASE/apps/frontend.app" --base "$BASE" --dry-run
  [ "$status" -eq 3 ]
  assert_output_contains "OutOfSync"
  [ ! -d "$BASE/live/frontend" ]
}

@test "sync-app updates a drifted file" {
  bash "$S/sync-app.sh" --app "$BASE/apps/frontend.app" --base "$BASE" >/dev/null
  echo "fe-v2" >"$BASE/src/frontend/deploy.yaml"
  run bash "$S/sync-app.sh" --app "$BASE/apps/frontend.app" --base "$BASE"
  assert_success
  assert_output_contains "UPDATE"
  [ "$(cat "$BASE/live/frontend/deploy.yaml")" = "fe-v2" ]
}

@test "sync-app leaves extras unless --prune" {
  bash "$S/sync-app.sh" --app "$BASE/apps/frontend.app" --base "$BASE" >/dev/null
  echo "junk" >"$BASE/live/frontend/rogue.yaml"
  run bash "$S/sync-app.sh" --app "$BASE/apps/frontend.app" --base "$BASE"
  assert_output_contains "IGNORE"
  [ -f "$BASE/live/frontend/rogue.yaml" ]
  run bash "$S/sync-app.sh" --app "$BASE/apps/frontend.app" --base "$BASE" --prune
  assert_success
  assert_output_contains "PRUNE"
  [ ! -f "$BASE/live/frontend/rogue.yaml" ]
}

@test "sync-app refuses an app-of-apps manifest" {
  run bash "$S/sync-app.sh" --app "$BASE/root.app" --base "$BASE"
  assert_failure
  assert_output_contains "app-of-apps"
}

@test "sync-app rejects a bad kind" {
  echo "kind = Nope" >"$BASE/bad.app"
  run bash "$S/sync-app.sh" --app "$BASE/bad.app" --base "$BASE"
  assert_failure
}

@test "sync-app rejects a missing manifest" {
  run bash "$S/sync-app.sh" --app "$BASE/nope.app" --base "$BASE"
  assert_failure
}

# ---- sync-root (app-of-apps) ----
@test "sync-root syncs every child app" {
  run bash "$S/sync-root.sh" --app "$BASE/root.app" --base "$BASE"
  assert_success
  assert_output_contains "2/2 apps synced"
  [ -f "$BASE/live/frontend/deploy.yaml" ]
  [ -f "$BASE/live/api/deploy.yaml" ]
}

@test "sync-root --dry-run exits non-zero when children are OutOfSync" {
  run bash "$S/sync-root.sh" --app "$BASE/root.app" --base "$BASE" --dry-run
  assert_failure
  assert_output_contains "OutOfSync"
}

@test "sync-root --dry-run exits 0 once everything is synced" {
  bash "$S/sync-root.sh" --app "$BASE/root.app" --base "$BASE" >/dev/null
  run bash "$S/sync-root.sh" --app "$BASE/root.app" --base "$BASE" --dry-run
  assert_success
  assert_output_contains "2/2 apps synced"
}

@test "sync-root rejects a leaf manifest (no apps)" {
  run bash "$S/sync-root.sh" --app "$BASE/apps/frontend.app" --base "$BASE"
  assert_failure
}

@test "sync-root rejects a missing apps dir" {
  {
    echo "kind = Application"
    echo "name = r"
    echo "apps = nope"
  } >"$BASE/badroot.app"
  run bash "$S/sync-root.sh" --app "$BASE/badroot.app" --base "$BASE"
  assert_failure
}
