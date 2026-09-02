#!/usr/bin/env bats
# platform/bootstrap.sh tests. Stub `kind` and `kubectl` are injected via $KIND
# and $KUBECTL so cluster lifecycle logic is exercised with no real Docker.
load ../../tests/test_helper

setup() {
  P="$REPO_ROOT/platform/bootstrap.sh"
  LOG="$BATS_TEST_TMPDIR/ops.log"
  STATE="$BATS_TEST_TMPDIR/clusters"
  : >"$LOG"
  : >"$STATE"
  export LOG STATE
  cat >"$BATS_TEST_TMPDIR/kind" <<'EOF'
#!/usr/bin/env bash
echo "kind $*" >>"$LOG"
case "$1" in
  get) cat "$STATE" ;;
  create) n=""; shift; while (($#)); do [[ "$1" == --name ]] && n="$2"; shift; done; echo "$n" >>"$STATE" ;;
  delete) n=""; shift; while (($#)); do [[ "$1" == --name ]] && n="$2"; shift; done; grep -vx "$n" "$STATE" >"$STATE.t" || true; mv "$STATE.t" "$STATE" ;;
esac
EOF
  cat >"$BATS_TEST_TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "kubectl $*" >>"$LOG"
if [[ "$1" == config ]]; then echo kind-bash-mastery; exit 0; fi
for a in "$@"; do case "$a" in get) echo 'node Ready'; exit 0;; apply) exit 0;; patch) exit 0;; esac; done
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/kind" "$BATS_TEST_TMPDIR/kubectl"
  export KIND="$BATS_TEST_TMPDIR/kind" KUBECTL="$BATS_TEST_TMPDIR/kubectl"
}

@test "bootstrap.sh is syntactically valid" {
  run bash -n "$P"
  assert_success
}

@test "missing subcommand -> usage, exit 2" {
  run bash "$P"
  [ "$status" -eq 2 ]
  assert_output_contains "usage:"
}

@test "unknown subcommand -> exit 2" {
  run bash "$P" bogus
  [ "$status" -eq 2 ]
}

@test "up reports missing kind -> exit 3" {
  export KIND="definitely-not-real-xyz"
  run bash "$P" up
  [ "$status" -eq 3 ]
  assert_output_contains "missing required tool"
}

@test "up creates a cluster and prints ONLY the context on stdout" {
  run bash "$P" up
  assert_success
  # stdout's last line is the clean context (logs/banner go to stderr)
  [ "${lines[-1]}" = "kind-bash-mastery" ]
  grep -q 'kind create cluster --name bash-mastery' "$LOG"
}

@test "up is idempotent: no re-create when the cluster exists" {
  echo "bash-mastery" >"$STATE"
  : >"$LOG"
  run bash "$P" up
  assert_success
  run grep -c 'kind create' "$LOG"
  [ "$output" -eq 0 ]
}

@test "up --metrics installs and patches metrics-server" {
  run bash "$P" up --metrics
  assert_success
  grep -q 'apply -f' "$LOG"
  grep -q 'patch deployment metrics-server' "$LOG"
}

@test "custom --name maps to context kind-NAME" {
  run bash "$P" up --name demo
  assert_success
  [ "${lines[-1]}" = "kind-demo" ]
}

@test "status has no REAL MODE banner" {
  run bash "$P" status
  assert_success
  run grep -c 'REAL MODE' <<<"$output"
  [ "$output" -eq 0 ]
}

@test "down deletes an existing cluster" {
  echo "bash-mastery" >"$STATE"
  run bash "$P" down
  assert_success
  run grep -qx 'bash-mastery' "$STATE"
  assert_failure
}

@test "down is idempotent when nothing exists -> exit 0" {
  run bash "$P" down
  assert_success
}
