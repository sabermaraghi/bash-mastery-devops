#!/usr/bin/env bats
# Day 25 Option 2 (real / kubectl) tests. A stub kubectl is injected via $KUBECTL
# so every guard is exercised with no real cluster. Cases that need a reachable
# cluster use a stub whose `version` succeeds; unreachable cases make it fail.
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day25/scripts"
  STUB="$BATS_TEST_TMPDIR/kubectl"
  ARGLOG="$BATS_TEST_TMPDIR/args.log"
  : >"$ARGLOG"
  export ARGLOG
  # Reachable stub: `version` succeeds; `apply`/`get`/`config` succeed and log args.
  cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$ARGLOG"
case "$1 $2" in
  *version*) exit 0 ;;
esac
for a in "$@"; do
  case "$a" in
    version) exit 0 ;;
    apply) echo "applied"; exit 0 ;;
    get) echo "NAME READY"; exit 0 ;;
  esac
done
# `config current-context`
if [[ "$1" == "config" && "$2" == "current-context" ]]; then
  echo "${STUB_CTX:-kind-bash-mastery}"; exit 0
fi
exit 0
EOF
  chmod +x "$STUB"
  export KUBECTL="$STUB"
  M="$BATS_TEST_TMPDIR/app.yaml"
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n' >"$M"
}

@test "real-kubectl.sh is syntactically valid" {
  run bash -n "$S/real-kubectl.sh"
  assert_success
}

@test "missing subcommand -> usage, exit 2" {
  run bash "$S/real-kubectl.sh"
  [ "$status" -eq 2 ]
  assert_output_contains "usage:"
}

@test "unknown subcommand -> exit 2" {
  run bash "$S/real-kubectl.sh" bogus
  [ "$status" -eq 2 ]
}

@test "reports missing tool when kubectl absent -> exit 3" {
  export KUBECTL="definitely-not-a-real-binary-xyz"
  run bash "$S/real-kubectl.sh" guard whatever
  [ "$status" -eq 3 ]
  assert_output_contains "missing required tool"
}

@test "apply requires explicit --context/--namespace/manifest" {
  run bash "$S/real-kubectl.sh" apply --context kind-x "$M"
  [ "$status" -eq 2 ]
}

@test "apply rejects an invalid namespace -> exit 2" {
  run bash "$S/real-kubectl.sh" apply --context kind-x --namespace 'Bad_NS' "$M"
  [ "$status" -eq 2 ]
  assert_output_contains "invalid namespace"
}

@test "apply rejects a missing manifest -> exit 2" {
  run bash "$S/real-kubectl.sh" apply --context kind-x --namespace demo /nope/x.yaml
  [ "$status" -eq 2 ]
  assert_output_contains "manifest not found"
}

@test "apply defaults to server dry-run" {
  run bash "$S/real-kubectl.sh" apply --context kind-x --namespace demo "$M"
  assert_success
  grep -q -- '--dry-run=server' "$ARGLOG"
  assert_output_contains "DRY-RUN"
}

@test "apply --apply performs a live apply (no dry-run flag)" {
  run bash "$S/real-kubectl.sh" apply --context kind-x --namespace demo --apply "$M"
  assert_success
  run grep -c -- '--dry-run=server' "$ARGLOG"
  [ "$output" -eq 0 ]
}

@test "apply refuses a protected context without --confirm -> exit 1" {
  run bash "$S/real-kubectl.sh" apply --context prod-eu --namespace demo --apply "$M"
  [ "$status" -eq 1 ]
  assert_output_contains "protected context"
}

@test "apply allows a protected context with --confirm" {
  run bash "$S/real-kubectl.sh" apply --context prod-eu --namespace demo --apply --confirm "$M"
  assert_success
}

@test "apply fails with exit 3 when the cluster is unreachable" {
  # stub whose version subcommand fails => unreachable
  cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do [[ "$a" == "version" ]] && exit 1; done
exit 0
EOF
  chmod +x "$STUB"
  run bash "$S/real-kubectl.sh" apply --context kind-x --namespace demo "$M"
  [ "$status" -eq 3 ]
  assert_output_contains "unreachable"
}

@test "guard passes when current-context matches" {
  export STUB_CTX="kind-bash-mastery"
  run bash "$S/real-kubectl.sh" guard kind-bash-mastery
  assert_success
  assert_output_contains "context OK"
}

@test "guard fails when current-context differs -> exit 1" {
  export STUB_CTX="prod-cluster"
  run bash "$S/real-kubectl.sh" guard kind-bash-mastery
  [ "$status" -eq 1 ]
  assert_output_contains "MISMATCH"
}

@test "get is read-only and defaults to pods" {
  run bash "$S/real-kubectl.sh" get --context kind-x --namespace demo
  assert_success
  grep -q 'get pods' "$ARGLOG"
  run grep -c -- 'apply' "$ARGLOG"
  [ "$output" -eq 0 ]
}
