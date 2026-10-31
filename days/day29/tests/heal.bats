#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day29/scripts"
  STATE="$BATS_TEST_TMPDIR/cluster"
  PODS="$STATE/pods"
  mkdir -p "$PODS"
  seed_pods 5
}

seed_pods() {
  rm -f "$PODS"/frontend-*
  local i
  for ((i = 0; i < $1; i++)); do echo "nginx:1.25" >"$PODS/frontend-$i"; done
}
hc() {
  local i n=0
  for ((i = 0; i < 5; i++)); do [ -s "$PODS/frontend-$i" ] && ! grep -q "CRASHED\|:bad" "$PODS/frontend-$i" && n=$((n + 1)); done
  echo "$n"
}

@test "all day29 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

# ---- health-lib ----
@test "probe_pod detects alive vs dead pods" {
  run bash -c "source '$S/health-lib.sh'; probe_pod '$PODS/frontend-0'"
  assert_success
  echo "CRASHED" >"$PODS/frontend-0"
  run bash -c "source '$S/health-lib.sh'; probe_pod '$PODS/frontend-0'"
  assert_failure
  run bash -c "source '$S/health-lib.sh'; probe_pod '$PODS/missing'"
  assert_failure
}

@test "probe_pod treats a :bad image as dead" {
  echo "app:bad" >"$PODS/frontend-0"
  run bash -c "source '$S/health-lib.sh'; probe_pod '$PODS/frontend-0'"
  assert_failure
}

# ---- heal ----
@test "heal restarts missing pods and reaches full health" {
  rm -f "$PODS/frontend-1" "$PODS/frontend-3"
  run bash "$S/heal.sh" --state-dir "$STATE" --name frontend --replicas 5 --image nginx:1.25
  assert_success
  assert_output_contains "RESTART frontend-1"
  assert_output_contains "healthy 5/5"
  [ "$(hc)" -eq 5 ]
}

@test "heal restarts a CRASHED pod" {
  echo "CRASHED" >"$PODS/frontend-2"
  run bash "$S/heal.sh" --state-dir "$STATE" --name frontend --replicas 5 --image nginx:1.25
  assert_success
  assert_output_contains "RESTART frontend-2"
  [ "$(cat "$PODS/frontend-2")" = "nginx:1.25" ]
}

@test "heal with policy Never reports but does not restart" {
  rm -f "$PODS/frontend-1"
  run bash "$S/heal.sh" --state-dir "$STATE" --name frontend --replicas 5 --image nginx:1.25 --restart-policy Never
  assert_failure
  assert_output_contains "UNHEALTHY frontend-1 (policy=Never"
  [ ! -f "$PODS/frontend-1" ]
}

@test "heal --dry-run changes nothing" {
  rm -f "$PODS/frontend-1"
  run bash "$S/heal.sh" --state-dir "$STATE" --name frontend --replicas 5 --image nginx:1.25 --dry-run
  assert_success
  assert_output_contains "plan:"
  [ ! -f "$PODS/frontend-1" ]
}

@test "heal rejects an invalid restart policy" {
  run bash "$S/heal.sh" --state-dir "$STATE" --name frontend --replicas 5 --image nginx:1.25 --restart-policy Sometimes
  assert_failure
}

@test "heal resets the backoff counter for a stable pod" {
  rm -f "$PODS/frontend-1"
  bash "$S/heal.sh" --state-dir "$STATE" --name frontend --replicas 5 --image nginx:1.25 >/dev/null
  # after healing, the pod is stable => counter file removed
  bash "$S/heal.sh" --state-dir "$STATE" --name frontend --replicas 5 --image nginx:1.25 >/dev/null
  [ ! -f "$STATE/restarts/frontend-1" ]
}

# ---- watchdog ----
@test "watchdog converges chaos damage back to healthy" {
  rm -f "$PODS/frontend-0" "$PODS/frontend-3"
  run bash "$S/watchdog.sh" --state-dir "$STATE" --name frontend --replicas 5 --image nginx:1.25 --max-iterations 5
  assert_success
  assert_output_contains "system healthy"
  [ "$(hc)" -eq 5 ]
}

@test "watchdog --once runs a single pass" {
  rm -f "$PODS/frontend-1"
  run bash "$S/watchdog.sh" --state-dir "$STATE" --name frontend --replicas 5 --image nginx:1.25 --once
  assert_success
  assert_output_contains "pass 1/1"
}

@test "watchdog stops at CrashLoopBackOff for a bad image" {
  BSTATE="$BATS_TEST_TMPDIR/broken"
  mkdir -p "$BSTATE/pods"
  echo "app:bad" >"$BSTATE/pods/broken-0"
  run bash "$S/watchdog.sh" --state-dir "$BSTATE" --name broken --replicas 1 --image app:bad --max-restarts 2 --max-iterations 5
  assert_failure
  assert_output_contains "CRASHLOOP broken-0"
  assert_output_contains "still degraded"
}

@test "watchdog requires the core flags" {
  run bash "$S/watchdog.sh" --name frontend
  assert_failure
}
