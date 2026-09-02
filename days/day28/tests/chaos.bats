#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day28/scripts"
  STATE="$BATS_TEST_TMPDIR/cluster"
  PODS="$STATE/pods"
  mkdir -p "$PODS"
  seed_pods 5
}

# create N pods named frontend-0..N-1
seed_pods() {
  rm -f "$PODS"/frontend-*
  local i
  for ((i = 0; i < $1; i++)); do echo "nginx:1.25" >"$PODS/frontend-$i"; done
}
count_live() { ls "$PODS"/frontend-* 2>/dev/null | grep -c . || true; }

@test "all day28 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

# ---- chaos-lib ----
@test "count_pods and blast_cap compute correctly" {
  run bash -c "source '$S/chaos-lib.sh'; count_pods '$PODS' frontend"
  assert_output_contains "5"
  run bash -c "source '$S/chaos-lib.sh'; blast_cap 5 50"
  assert_output_contains "2"
}

@test "pick_victims is deterministic for a given seed" {
  a=$(bash -c "source '$S/chaos-lib.sh'; pick_victims '$PODS' frontend 2 7")
  b=$(bash -c "source '$S/chaos-lib.sh'; pick_victims '$PODS' frontend 2 7")
  [ "$a" = "$b" ]
  # count of victims equals requested
  [ "$(printf '%s\n' "$a" | grep -c .)" -eq 2 ]
}

# ---- chaos-kill ----
@test "chaos-kill deletes the requested number of pods" {
  run bash "$S/chaos-kill.sh" --state-dir "$STATE" --name frontend --expect 5 --count 2 --seed 7
  assert_success
  assert_output_contains "killed 2/5"
  [ "$(count_live)" -eq 3 ]
}

@test "chaos-kill refuses when not in steady state" {
  seed_pods 3
  run bash "$S/chaos-kill.sh" --state-dir "$STATE" --name frontend --expect 5 --count 1
  assert_failure
  assert_output_contains "steady state"
}

@test "chaos-kill enforces the blast radius" {
  run bash "$S/chaos-kill.sh" --state-dir "$STATE" --name frontend --expect 5 --count 4 --seed 7
  assert_failure
  assert_output_contains "blast radius exceeded"
  [ "$(count_live)" -eq 5 ]
}

@test "chaos-kill allows override with a higher --max-percent" {
  run bash "$S/chaos-kill.sh" --state-dir "$STATE" --name frontend --expect 5 --count 4 --seed 7 --max-percent 100
  assert_success
  [ "$(count_live)" -eq 1 ]
}

@test "chaos-kill --percent rounds up" {
  run bash "$S/chaos-kill.sh" --state-dir "$STATE" --name frontend --expect 5 --percent 30 --seed 7
  assert_success
  # 30% of 5 = 1.5 -> 2
  assert_output_contains "killed 2/5"
}

@test "chaos-kill --dry-run kills nothing" {
  run bash "$S/chaos-kill.sh" --state-dir "$STATE" --name frontend --expect 5 --count 2 --seed 7 --dry-run
  assert_success
  assert_output_contains "planned"
  [ "$(count_live)" -eq 5 ]
}

# ---- chaos-run ----
@test "experiment passes when heal restores steady state" {
  HEAL="for i in 0 1 2 3 4; do echo nginx:1.25 > '$PODS/frontend-'\$i; done"
  run bash "$S/chaos-run.sh" --state-dir "$STATE" --name frontend --expect 5 --count 2 --seed 7 --heal-cmd "$HEAL"
  assert_success
  assert_output_contains "EXPERIMENT PASSED"
  [ "$(count_live)" -eq 5 ]
}

@test "experiment fails with no heal command" {
  run bash "$S/chaos-run.sh" --state-dir "$STATE" --name frontend --expect 5 --count 2 --seed 7
  assert_failure
  assert_output_contains "EXPERIMENT FAILED"
}

@test "experiment aborts when baseline is not steady" {
  seed_pods 3
  run bash "$S/chaos-run.sh" --state-dir "$STATE" --name frontend --expect 5 --count 1
  assert_failure
  assert_output_contains "ABORT"
}

@test "chaos-kill requires state-dir, name and expect" {
  run bash "$S/chaos-kill.sh" --name frontend
  assert_failure
}
