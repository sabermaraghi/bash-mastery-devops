#!/usr/bin/env bats
# real-cost.sh tests. Stub `kubectl` via $KUBECTL so no real cluster is needed.
# The stub reports three Deployments and per-selector `kubectl top` usage that
# reproduces the offline lesson's WASTE / RISK / OK example.
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day30/scripts/real-cost.sh"
  cat >"$BATS_TEST_TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"
[[ "$args" == *version* ]] && exit 0
[[ "$args" == *"config current-context"* ]] && { echo kind-x; exit 0; }
if [[ "$args" == *"get deploy"* ]]; then
  printf 'frontend 5 500m 512Mi\napi 3 250m 256Mi\ncache 2 200m 512Mi\n'
  exit 0
fi
if [[ "$args" == *"top pods"* ]]; then
  if [[ "$args" != *"-l "* ]]; then echo 'x 1m 1Mi'; exit 0; fi
  if [[ "$args" == *"app=frontend"* ]]; then printf 'frontend-a 100m 200Mi\nfrontend-b 100m 200Mi\n'; exit 0; fi
  if [[ "$args" == *"app=api"* ]]; then printf 'api-a 230m 180Mi\n'; exit 0; fi
  if [[ "$args" == *"app=cache"* ]]; then printf 'cache-a 120m 300Mi\n'; exit 0; fi
  exit 0
fi
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/kubectl"
  export KUBECTL="$BATS_TEST_TMPDIR/kubectl"
  C=(--context kind-x --namespace default)
}

@test "real-cost.sh is syntactically valid" {
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

@test "report prices each Deployment's requests" {
  run bash "$S" report "${C[@]}"
  assert_success
  assert_output_contains "frontend"
  assert_output_contains "63.88"
}

@test "report totals the monthly cost" {
  run bash "$S" report "${C[@]}"
  assert_success
  assert_output_contains "TOTAL"
  assert_output_contains "95.01"
}

@test "report converts CPU and memory quantities to millicores and MiB" {
  run bash "$S" report "${C[@]}"
  assert_success
  # 500m -> 500 millicores, 512Mi -> 512 MiB
  assert_output_contains "500      512"
}

@test "rightsize flags WASTE, RISK and OK and gates on failure" {
  run bash "$S" rightsize "${C[@]}"
  assert_failure 1
  assert_output_contains "WASTE"
  assert_output_contains "RISK"
  assert_output_contains "OK"
  assert_output_contains "workloads need right-sizing"
}

@test "rightsize sums the potential monthly savings" {
  run bash "$S" rightsize "${C[@]}"
  assert_output_contains "Potential monthly savings: \$30.75"
}

@test "rightsize honors a tolerant band and passes clean" {
  run bash "$S" rightsize "${C[@]}" --low 5 --high 99
  assert_success
  assert_output_contains "all workloads right-sized"
}

@test "report reports missing kubectl -> exit 3" {
  KUBECTL=definitely-no-kubectl-xyz run bash "$S" report "${C[@]}"
  assert_failure 3
}

@test "rightsize degrades gracefully when metrics are unavailable -> exit 3" {
  cat >"$BATS_TEST_TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"
[[ "$args" == *version* ]] && exit 0
[[ "$args" == *"get deploy"* ]] && { printf 'frontend 5 500m 512Mi\n'; exit 0; }
[[ "$args" == *"top pods"* ]] && exit 1
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/kubectl"
  run bash "$S" rightsize "${C[@]}"
  assert_failure 3
  assert_output_contains "metrics unavailable"
}

@test "report rejects an invalid namespace -> exit 2" {
  run bash "$S" report --context kind-x --namespace Bad_NS
  assert_failure 2
  assert_output_contains "invalid namespace"
}

@test "report errors when there are no Deployments" {
  cat >"$BATS_TEST_TMPDIR/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"
[[ "$args" == *version* ]] && exit 0
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/kubectl"
  run bash "$S" report "${C[@]}"
  assert_failure
  assert_output_contains "no Deployments"
}
