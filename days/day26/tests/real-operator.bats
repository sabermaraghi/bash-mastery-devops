#!/usr/bin/env bats
# real-operator.sh tests. A stub `kubectl` is injected via $KUBECTL so the whole
# reconcile pattern is exercised with no real cluster. The real path also
# `skip`s cleanly if kubectl is genuinely absent and unstubbed.
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day26/scripts/real-operator.sh"
  LOG="$BATS_TEST_TMPDIR/k.log"
  : >"$LOG"
  export LOG
  CR="$BATS_TEST_TMPDIR/frontend.cr"
  printf 'kind = WidgetSet\nname = frontend\nreplicas = 3\nimage = nginx:1.25\n' >"$CR"
  cat >"$BATS_TEST_TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "kubectl $*" >>"$LOG"
args="$*"
[[ "$args" == *version* ]] && exit 0
if [[ "$args" == *"get deployment"* ]]; then
  [[ "$args" == *spec.replicas* ]] && { echo 3; exit 0; }
  [[ "$args" == *status.readyReplicas* ]] && { echo "${FAKE_READY-3}"; exit 0; }
fi
[[ "$args" == *apply* ]] && { cat >/dev/null; echo configured; exit 0; }
[[ "$args" == *delete* ]] && { echo deleted; exit 0; }
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/kubectl"
  export KUBECTL="$BATS_TEST_TMPDIR/kubectl"
}

@test "real-operator.sh is syntactically valid" {
  run bash -n "$S"
  assert_success
}

@test "no subcommand -> usage, exit 2" {
  run bash "$S"
  [ "$status" -eq 2 ]
  assert_output_contains "usage:"
}

@test "unknown subcommand -> exit 2" {
  run bash "$S" bogus
  [ "$status" -eq 2 ]
}

@test "missing kubectl -> exit 3" {
  export KUBECTL="definitely-not-real-xyz"
  run bash "$S" reconcile --cr "$CR" --context kind-x --namespace demo
  [ "$status" -eq 3 ]
}

@test "reconcile requires --namespace -> exit 2" {
  run bash "$S" reconcile --cr "$CR" --context kind-x
  [ "$status" -eq 2 ]
}

@test "invalid namespace -> exit 2" {
  run bash "$S" reconcile --cr "$CR" --context kind-x --namespace 'Bad_NS'
  [ "$status" -eq 2 ]
}

@test "non-uint replicas -> exit 2" {
  printf 'kind = WidgetSet\nname = x\nreplicas = -1\nimage = nginx\n' >"$BATS_TEST_TMPDIR/bad.cr"
  run bash "$S" reconcile --cr "$BATS_TEST_TMPDIR/bad.cr" --context kind-x --namespace demo
  [ "$status" -eq 2 ]
}

@test "non-WidgetSet kind -> exit 2" {
  printf 'kind = Other\nname = x\nreplicas = 1\nimage = nginx\n' >"$BATS_TEST_TMPDIR/other.cr"
  run bash "$S" reconcile --cr "$BATS_TEST_TMPDIR/other.cr" --context kind-x --namespace demo
  [ "$status" -eq 2 ]
}

@test "reconcile defaults to server dry-run" {
  run bash "$S" reconcile --cr "$CR" --context kind-x --namespace demo
  assert_success
  grep -q 'apply -f - --dry-run=server' "$LOG"
}

@test "--apply drops dry-run and pipes the manifest" {
  run bash "$S" reconcile --cr "$CR" --context kind-x --namespace demo --apply
  assert_success
  grep -q 'apply -f -' "$LOG"
  run grep -c 'dry-run' "$LOG"
  [ "$output" -eq 0 ]
}

@test "protected context refuses to mutate without --confirm -> exit 1" {
  run bash "$S" reconcile --cr "$CR" --context prod --namespace demo --apply
  [ "$status" -eq 1 ]
}

@test "protected context proceeds with --confirm" {
  run bash "$S" reconcile --cr "$CR" --context prod --namespace demo --apply --confirm
  assert_success
}

@test "status reports Ready when ready == desired" {
  run bash "$S" status --cr "$CR" --context kind-x --namespace demo
  assert_success
  assert_output_contains "phase=Ready"
}

@test "status reports Scaling when short" {
  FAKE_READY=1 run bash "$S" status --cr "$CR" --context kind-x --namespace demo
  assert_success
  assert_output_contains "phase=Scaling"
}

@test "delete uses --ignore-not-found" {
  run bash "$S" delete --cr "$CR" --context kind-x --namespace demo
  assert_success
  grep -q 'delete deployment frontend --ignore-not-found' "$LOG"
}

@test "watch --once reconciles every CR in the dir" {
  mkdir -p "$BATS_TEST_TMPDIR/crs"
  cp "$CR" "$BATS_TEST_TMPDIR/crs/frontend.cr"
  printf 'kind = WidgetSet\nname = api\nreplicas = 2\nimage = redis:7\n' >"$BATS_TEST_TMPDIR/crs/api.cr"
  run bash "$S" watch --cr-dir "$BATS_TEST_TMPDIR/crs" --context kind-x --namespace demo --once --apply
  assert_success
  run grep -c 'apply -f -' "$LOG"
  [ "$output" -eq 2 ]
}
