#!/usr/bin/env bats
# real-heal.sh tests. Stub `kubectl` via $KUBECTL so no real cluster is needed.
# Deployment state is driven by files ($SPEC / $READY / $PODS) so tests can
# simulate drift, readiness, and crashloops. `scale` calls are recorded to $LOG.
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day29/scripts/real-heal.sh"
  export LOG="$BATS_TEST_TMPDIR/k.log"
  : >"$LOG"
  export SPEC="$BATS_TEST_TMPDIR/spec"
  export READY="$BATS_TEST_TMPDIR/ready"
  export PODS="$BATS_TEST_TMPDIR/pods"
  cat >"$BATS_TEST_TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "kubectl $*" >>"$LOG"
args="$*"
[[ "$args" == *version* ]] && exit 0
[[ "$args" == *"config current-context"* ]] && { echo kind-x; exit 0; }
if [[ "$args" == *"get deploy"* && "$args" == *"spec.replicas"* ]]; then cat "$SPEC" 2>/dev/null; exit 0; fi
if [[ "$args" == *"get deploy"* && "$args" == *"readyReplicas"* ]]; then cat "$READY" 2>/dev/null; exit 0; fi
if [[ "$args" == *"get pods"* ]]; then cat "$PODS" 2>/dev/null; exit 0; fi
if [[ "$args" == *"scale deploy"* ]]; then n="${args##*--replicas=}"; n="${n%% *}"; echo "$n" >"$SPEC"; echo "$n" >"$READY"; exit 0; fi
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/kubectl"
  export KUBECTL="$BATS_TEST_TMPDIR/kubectl"
  C=(--context kind-x --namespace frontend --deployment frontend --replicas 3)
}

@test "real-heal.sh is syntactically valid" {
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

@test "heal reports healthy when ready matches desired" {
  echo 3 >"$SPEC"
  echo 3 >"$READY"
  : >"$PODS"
  run bash "$S" heal "${C[@]}"
  assert_success
  assert_output_contains "report: healthy 3/3"
}

@test "heal reports drift but does not scale without --apply" {
  echo 2 >"$SPEC"
  echo 2 >"$READY"
  : >"$PODS"
  run bash "$S" heal "${C[@]}"
  assert_failure
  assert_output_contains "SCALE frontend 2 -> 3"
  [ "$(grep -c "scale deploy" "$LOG")" -eq 0 ]
}

@test "heal --apply reconciles the drift by scaling" {
  echo 2 >"$SPEC"
  echo 2 >"$READY"
  : >"$PODS"
  run bash "$S" heal "${C[@]}" --apply
  assert_success
  assert_output_contains "reconciled: healthy 3/3"
  [ "$(grep -c "scale deploy" "$LOG")" -eq 1 ]
}

@test "heal surfaces a CrashLoopBackOff pod" {
  echo 3 >"$SPEC"
  echo 2 >"$READY"
  printf 'frontend-x 7 CrashLoopBackOff\n' >"$PODS"
  run bash "$S" heal "${C[@]}"
  assert_failure
  assert_output_contains "CRASHLOOP frontend-x"
}

@test "heal flags a pod past the restart budget" {
  echo 3 >"$SPEC"
  echo 3 >"$READY"
  printf 'frontend-y 5 Running\n' >"$PODS"
  run bash "$S" heal "${C[@]}" --max-restarts 2
  assert_failure
  assert_output_contains "CRASHLOOP frontend-y"
}

@test "heal ignores a pod under the restart budget" {
  echo 3 >"$SPEC"
  echo 3 >"$READY"
  printf 'frontend-y 1 Running\n' >"$PODS"
  run bash "$S" heal "${C[@]}" --max-restarts 2
  assert_success
  assert_output_contains "0 crashloop"
}

@test "heal on a protected context refuses without --confirm" {
  echo 3 >"$SPEC"
  echo 3 >"$READY"
  : >"$PODS"
  PROTECTED_CONTEXTS=kind-x run bash "$S" heal "${C[@]}"
  assert_failure
  assert_output_contains "is protected"
}

@test "heal on a protected context proceeds with --confirm" {
  echo 3 >"$SPEC"
  echo 3 >"$READY"
  : >"$PODS"
  PROTECTED_CONTEXTS=kind-x run bash "$S" heal "${C[@]}" --confirm
  assert_success
}

@test "heal reports missing kubectl -> exit 3" {
  echo 3 >"$SPEC"
  echo 3 >"$READY"
  : >"$PODS"
  KUBECTL=definitely-no-kubectl-xyz run bash "$S" heal "${C[@]}"
  assert_failure 3
}

@test "heal rejects an invalid namespace -> exit 2" {
  run bash "$S" heal --context kind-x --namespace Bad_NS --deployment frontend --replicas 3
  assert_failure 2
  assert_output_contains "invalid namespace"
}

@test "heal errors when the deployment does not exist" {
  : >"$SPEC"
  : >"$READY"
  : >"$PODS"
  run bash "$S" heal "${C[@]}"
  assert_failure
  assert_output_contains "not found"
}

@test "watch converges after reconciling drift" {
  echo 1 >"$SPEC"
  echo 1 >"$READY"
  : >"$PODS"
  run bash "$S" watch "${C[@]}" --apply --max-iterations 3 --interval 0
  assert_success
  assert_output_contains "watchdog: Deployment healthy"
}

@test "watch reports degraded when a crashloop never clears" {
  echo 3 >"$SPEC"
  echo 2 >"$READY"
  printf 'frontend-x 9 CrashLoopBackOff\n' >"$PODS"
  run bash "$S" watch "${C[@]}" --apply --max-iterations 2 --interval 0
  assert_failure
  assert_output_contains "still degraded"
}
