#!/usr/bin/env bats
# real-argo.sh tests. Stub `kubectl` via $KUBECTL; `argocd` CLI is forced absent
# (ARGOCD=<nonexistent>) so the kubectl fallback paths are exercised too. No
# real cluster or ArgoCD needed. `render` is pure translation (no tools).
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day27/scripts/real-argo.sh"
  LOG="$BATS_TEST_TMPDIR/k.log"
  : >"$LOG"
  export LOG
  LEAF="$REPO_ROOT/days/day27/examples/apps/frontend.app"
  ROOT="$REPO_ROOT/days/day27/examples/root.app"
  REPO="https://github.com/me/repo.git"
  cat >"$BATS_TEST_TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "kubectl $*" >>"$LOG"
args="$*"
[[ "$args" == *version* ]] && exit 0
if [[ "$args" == *"get application"* ]]; then
  [[ "$args" == *sync.status* ]] && { echo Synced; exit 0; }
  [[ "$args" == *health.status* ]] && { echo Healthy; exit 0; }
fi
[[ "$args" == *"get secret argocd-initial-admin-secret"* ]] && { printf 's3cret' | base64; exit 0; }
if [[ "$args" == *apply* ]]; then
  # only drain stdin for `apply -f -`; a file/URL apply has no pipe, so an
  # unconditional `cat` would block forever waiting on the terminal.
  [[ "$args" == *"-f -"* ]] && cat >/dev/null 2>&1
  echo configured; exit 0
fi
[[ "$args" == *annotate* ]] && { echo annotated; exit 0; }
[[ "$args" == *"create namespace"* ]] && { echo 'apiVersion: v1'; exit 0; }
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/kubectl"
  export KUBECTL="$BATS_TEST_TMPDIR/kubectl"
  export ARGOCD="definitely-no-argocd-xyz"
}

@test "real-argo.sh is syntactically valid" {
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

@test "render works offline (no tools) and emits an Application" {
  export KUBECTL="nope-not-real"
  run bash "$S" render --app "$LEAF" --repo-url "$REPO"
  assert_success
  assert_output_contains "kind: Application"
  assert_output_contains "repoURL: https://github.com/me/repo.git"
}

@test "leaf render: path = source, dest namespace defaults to app name" {
  run bash "$S" render --app "$LEAF" --repo-url "$REPO"
  assert_success
  assert_output_contains "path: days/day27/examples/desired/frontend"
  assert_output_contains "namespace: frontend"
}

@test "--prune sets prune: true" {
  run bash "$S" render --app "$LEAF" --repo-url "$REPO" --prune
  assert_success
  assert_output_contains "prune: true"
}

@test "root app-of-apps render: path = apps dir" {
  run bash "$S" render --app "$ROOT" --repo-url "$REPO"
  assert_success
  assert_output_contains "path: days/day27/examples/apps"
}

@test "real root render: path = argo-apps dir of real child Applications" {
  run bash "$S" render --app "$REPO_ROOT/days/day27/examples/root-real.app" --repo-url "$REPO"
  assert_success
  assert_output_contains "path: days/day27/examples/argo-apps"
}

@test "render-children writes a real Application per leaf (no tools needed)" {
  export KUBECTL="nope-not-real"
  out="$BATS_TEST_TMPDIR/argo-apps"
  run bash "$S" render-children --repo-url "$REPO" --out "$out"
  assert_success
  [ -f "$out/frontend.yaml" ]
  [ -f "$out/api.yaml" ]
  grep -q 'kind: Application' "$out/frontend.yaml"
  grep -q 'repoURL: https://github.com/me/repo.git' "$out/frontend.yaml"
  grep -q 'path: days/day27/examples/desired/frontend' "$out/frontend.yaml"
}

@test "render-children requires --repo-url -> exit 2" {
  run bash "$S" render-children
  [ "$status" -eq 2 ]
}

@test "render requires --repo-url -> exit 2" {
  run bash "$S" render --app "$LEAF"
  [ "$status" -eq 2 ]
}

@test "install reports missing kubectl -> exit 3" {
  export KUBECTL="definitely-not-real-xyz"
  run bash "$S" install --context kind-x
  [ "$status" -eq 3 ]
}

@test "install preview does not apply the manifest" {
  run bash "$S" install --context kind-x
  assert_success
  run grep -c 'apply -f' "$LOG"
  [ "$output" -eq 0 ]
}

@test "install --apply applies the ArgoCD manifest server-side" {
  run bash "$S" install --context kind-x --apply
  assert_success
  grep -q 'apply --server-side --force-conflicts -f https' "$LOG"
}

@test "install refuses protected context without --confirm -> exit 1" {
  run bash "$S" install --context prod --apply
  [ "$status" -eq 1 ]
}

@test "apply defaults to server dry-run" {
  run bash "$S" apply --app "$LEAF" --context kind-x --repo-url "$REPO"
  assert_success
  grep -q 'apply -f - --dry-run=server' "$LOG"
}

@test "apply --apply drops dry-run" {
  run bash "$S" apply --app "$LEAF" --context kind-x --repo-url "$REPO" --apply
  assert_success
  run grep -c 'dry-run' "$LOG"
  [ "$output" -eq 0 ]
}

@test "apply refuses protected context without --confirm -> exit 1" {
  run bash "$S" apply --app "$LEAF" --context prod --repo-url "$REPO" --apply
  [ "$status" -eq 1 ]
}

@test "sync falls back to a kubectl hard refresh when argocd CLI is absent" {
  run bash "$S" sync --app "$LEAF" --context kind-x
  assert_success
  grep -q 'annotate application frontend argocd.argoproj.io/refresh=hard' "$LOG"
}

@test "sync --use-cli errors when argocd CLI is absent -> exit 3" {
  run bash "$S" sync --app "$LEAF" --context kind-x --use-cli
  [ "$status" -eq 3 ]
}

@test "status reads sync/health via kubectl fallback" {
  run bash "$S" status --app "$LEAF" --context kind-x
  assert_success
  assert_output_contains "sync=Synced"
  assert_output_contains "health=Healthy"
}

@test "status --use-cli errors when argocd CLI is absent -> exit 3" {
  run bash "$S" status --app "$LEAF" --context kind-x --use-cli
  [ "$status" -eq 3 ]
}

@test "status warns when the Application object does not exist yet" {
  cat >"$BATS_TEST_TMPDIR/kc-missing" <<'EOF'
#!/usr/bin/env bash
args="$*"
[[ "$args" == *version* ]] && exit 0
[[ "$args" == *"get application"* ]] && exit 1
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/kc-missing"
  export KUBECTL="$BATS_TEST_TMPDIR/kc-missing"
  run bash "$S" status --app "$LEAF" --context kind-x
  assert_success
  assert_output_contains "not found"
}

@test "status reports 'not reconciled yet' when the object exists but has no status" {
  cat >"$BATS_TEST_TMPDIR/kc-pending" <<'EOF'
#!/usr/bin/env bash
args="$*"
[[ "$args" == *version* ]] && exit 0
[[ "$args" == *"get application"* ]] && exit 0
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/kc-pending"
  export KUBECTL="$BATS_TEST_TMPDIR/kc-pending"
  run bash "$S" status --app "$LEAF" --context kind-x
  assert_success
  assert_output_contains "not reconciled yet"
}

@test "ui reports missing kubectl -> exit 3" {
  export KUBECTL="definitely-not-real-xyz"
  run bash "$S" ui --context kind-x
  [ "$status" -eq 3 ]
}

@test "admin-password decodes the initial admin secret" {
  run bash "$S" admin-password --context kind-x
  assert_success
  assert_output_contains "s3cret"
}
