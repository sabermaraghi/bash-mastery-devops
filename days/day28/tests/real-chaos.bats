#!/usr/bin/env bats
# real-chaos.sh tests. Stub `kubectl` via $KUBECTL so no real cluster is needed.
# The stub reports a fixed set of Running pods and records `delete pod` calls to
# a log so we can assert whether pods were actually deleted.
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day28/scripts/real-chaos.sh"
  LOG="$BATS_TEST_TMPDIR/k.log"
  : >"$LOG"
  export LOG
  cat >"$BATS_TEST_TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "kubectl $*" >>"$LOG"
args="$*"
[[ "$args" == *version* ]] && exit 0
[[ "$args" == *"config current-context"* ]] && { echo kind-x; exit 0; }
if [[ "$args" == *"get pods"* ]]; then
  for i in 0 1 2 3 4; do echo "frontend-$i Running"; done
  exit 0
fi
[[ "$args" == *"delete pod"* ]] && { echo deleted; exit 0; }
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/kubectl"
  export KUBECTL="$BATS_TEST_TMPDIR/kubectl"
}

@test "real-chaos.sh is syntactically valid" {
  run bash -n "$S"
  assert_success
}

@test "no subcommand -> usage, exit 2" {
  run bash "$S"
  assert_failure 2
}

@test "unknown subcommand -> exit 2" {
  run bash "$S" frobnicate
  assert_failure 2
}

@test "kill refuses when not in steady state" {
  run bash "$S" kill --context kind-x --namespace frontend --selector app=frontend --expect 3
  assert_failure
  assert_output_contains "not in steady state"
}

@test "kill enforces the blast radius" {
  run bash "$S" kill --context kind-x --namespace frontend --selector app=frontend --expect 5 --count 4
  assert_failure
  assert_output_contains "blast radius exceeded"
}

@test "kill preview lists victims but deletes nothing" {
  run bash "$S" kill --context kind-x --namespace frontend --selector app=frontend --expect 5 --count 2 --seed 7
  assert_success
  assert_output_contains "KILL frontend-"
  assert_output_contains "preview: killed 2/5"
  [ "$(grep -c "delete pod" "$LOG")" -eq 0 ]
}

@test "kill --apply actually deletes pods" {
  run bash "$S" kill --context kind-x --namespace frontend --selector app=frontend --expect 5 --count 1 --seed 7 --apply
  assert_success
  assert_output_contains "injected: killed 1/5"
  [ "$(grep -c "delete pod" "$LOG")" -eq 1 ]
}

@test "kill picks the same victims for the same seed" {
  run bash "$S" kill --context kind-x --namespace frontend --selector app=frontend --expect 5 --count 2 --seed 7
  first="$output"
  run bash "$S" kill --context kind-x --namespace frontend --selector app=frontend --expect 5 --count 2 --seed 7
  [ "$output" = "$first" ]
}

@test "kill --percent computes the count and still caps the blast radius" {
  run bash "$S" kill --context kind-x --namespace frontend --selector app=frontend --expect 5 --percent 40 --seed 7
  assert_success
  assert_output_contains "preview: killed 2/5"
}

@test "kill on a protected context refuses without --confirm" {
  PROTECTED_CONTEXTS=kind-x run bash "$S" kill --context kind-x --namespace frontend --selector app=frontend --expect 5 --count 1
  assert_failure
  assert_output_contains "is protected"
}

@test "kill reports missing kubectl -> exit 3" {
  KUBECTL=definitely-no-kubectl-xyz run bash "$S" kill --context kind-x --namespace frontend --selector app=frontend --expect 5
  assert_failure 3
}

@test "kill rejects an invalid namespace -> exit 2" {
  run bash "$S" kill --context kind-x --namespace Bad_NS --selector app=frontend --expect 5
  assert_failure 2
  assert_output_contains "invalid namespace"
}

@test "run passes when the cluster stays in steady state" {
  run bash "$S" run --context kind-x --namespace frontend --selector app=frontend --expect 5 --count 2 --seed 7 --wait 0 --apply
  assert_success
  assert_output_contains "EXPERIMENT PASSED"
}

@test "run preview (no --apply) skips wait/verify" {
  run bash "$S" run --context kind-x --namespace frontend --selector app=frontend --expect 5 --count 2 --seed 7
  assert_success
  assert_output_contains "[preview]"
}

@test "run aborts when the baseline is not steady" {
  run bash "$S" run --context kind-x --namespace frontend --selector app=frontend --expect 9 --wait 0 --apply
  assert_failure
  assert_output_contains "ABORT: not in steady state"
}
