#!/usr/bin/env bats
# real-gitops.bats — Day 24 Option 2 (real GitOps via kubectl).
#
# We never touch a real cluster here. A fake `kubectl` on PATH records the args
# it was called with and returns a configurable exit code, so we can assert the
# script builds the right commands and maps kubectl's diff exit codes correctly.
load ../../../tests/test_helper

SCRIPT="$REPO_ROOT/days/day24/scripts/real-gitops.sh"

setup() {
  FAKE="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE"
  DIR="$BATS_TEST_TMPDIR/manifests"
  mkdir -p "$DIR"
  printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: demo\n' >"$DIR/ns.yaml"
  ARGLOG="$BATS_TEST_TMPDIR/kubectl-args.log"
}

# Write a fake kubectl. $1 = exit code for the `diff`/`apply` verb.
# `version` always succeeds so the cluster looks reachable.
make_kubectl() {
  local verb_rc="${1:-0}"
  cat >"$FAKE/kubectl" <<EOF
#!/usr/bin/env bash
echo "KARGS: \$*" >>"$ARGLOG"
for a in "\$@"; do
  case "\$a" in
    version) exit 0 ;;
    apply|diff) exit $verb_rc ;;
  esac
done
exit 0
EOF
  chmod +x "$FAKE/kubectl"
}

@test "real-gitops.sh is syntactically valid" {
  run bash -n "$SCRIPT"
  assert_success
}

@test "missing subcommand shows usage (exit 2)" {
  run bash "$SCRIPT"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output_contains "usage:"
}

@test "unknown subcommand shows usage (exit 2)" {
  run bash "$SCRIPT" frobnicate --dir "$DIR"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output_contains "unknown subcommand"
}

@test "--help exits 2 with usage" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 2 ]
  assert_output_contains "usage:"
}

@test "missing kubectl -> exit 3" {
  # empty fake bin dir: no kubectl on PATH
  run env PATH="$FAKE:/usr/bin:/bin" bash "$SCRIPT" reconcile --dir "$DIR"
  [ "$status" -eq 3 ]
}

@test "reconcile requires a directory that exists" {
  make_kubectl 0
  run env PATH="$FAKE:$PATH" bash "$SCRIPT" reconcile --dir "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
}

@test "reconcile applies the manifests (kubectl apply -f)" {
  make_kubectl 0
  run env PATH="$FAKE:$PATH" bash "$SCRIPT" reconcile --dir "$DIR" --namespace demo
  assert_success
  grep -q "apply -f $DIR" "$ARGLOG"
  grep -q -- "--namespace demo" "$ARGLOG"
}

@test "reconcile --dry-run uses server-side dry run" {
  make_kubectl 0
  run env PATH="$FAKE:$PATH" bash "$SCRIPT" reconcile --dir "$DIR" --dry-run
  assert_success
  grep -q -- "--dry-run=server" "$ARGLOG"
}

@test "reconcile --prune passes the label selector" {
  make_kubectl 0
  run env PATH="$FAKE:$PATH" bash "$SCRIPT" reconcile --dir "$DIR" --prune
  assert_success
  grep -q -- "--prune" "$ARGLOG"
  grep -q "app.kubernetes.io/managed-by=day24-gitops" "$ARGLOG"
}

@test "reconcile fails when kubectl apply fails" {
  make_kubectl 1
  run env PATH="$FAKE:$PATH" bash "$SCRIPT" reconcile --dir "$DIR"
  [ "$status" -eq 1 ]
}

@test "drift: clean cluster (kubectl diff rc 0) -> exit 0" {
  make_kubectl 0
  run env PATH="$FAKE:$PATH" bash "$SCRIPT" drift --dir "$DIR"
  assert_success
  assert_output_contains "no drift"
}

@test "drift: diverged cluster (kubectl diff rc 1) -> exit 1" {
  make_kubectl 1
  run env PATH="$FAKE:$PATH" bash "$SCRIPT" drift --dir "$DIR"
  [ "$status" -eq 1 ]
  assert_output_contains "drift detected"
}

@test "drift: kubectl diff hard error (rc 2) -> exit 3" {
  make_kubectl 2
  run env PATH="$FAKE:$PATH" bash "$SCRIPT" drift --dir "$DIR"
  [ "$status" -eq 3 ]
}

@test "drift rejects reconcile-only flags" {
  make_kubectl 0
  run env PATH="$FAKE:$PATH" bash "$SCRIPT" drift --dir "$DIR" --prune
  [ "$status" -eq 2 ]
  assert_output_contains "reconcile-only"
}

@test "unreachable cluster -> exit 3" {
  # kubectl exists but `version` fails: simulate an unreachable cluster.
  cat >"$FAKE/kubectl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = version ] && exit 1; done
exit 0
EOF
  chmod +x "$FAKE/kubectl"
  run env PATH="$FAKE:$PATH" bash "$SCRIPT" reconcile --dir "$DIR"
  [ "$status" -eq 3 ]
}
