#!/usr/bin/env bats
load ../../../tests/test_helper

setup() {
  S="$REPO_ROOT/days/day30/scripts"
  DIR="$BATS_TEST_TMPDIR/workloads"
  mkdir -p "$DIR"
  # waste: 20% cpu util
  {
    echo "name = frontend"
    echo "replicas = 5"
    echo "cpu_request = 500"
    echo "mem_request = 512"
    echo "cpu_usage = 100"
    echo "mem_usage = 200"
  } >"$DIR/frontend.workload"
  # risk: 92% cpu util
  {
    echo "name = api"
    echo "replicas = 3"
    echo "cpu_request = 250"
    echo "mem_request = 256"
    echo "cpu_usage = 230"
    echo "mem_usage = 180"
  } >"$DIR/api.workload"
  # ok: 60% cpu util
  {
    echo "name = cache"
    echo "replicas = 2"
    echo "cpu_request = 200"
    echo "mem_request = 512"
    echo "cpu_usage = 120"
    echo "mem_usage = 300"
  } >"$DIR/cache.workload"
}

@test "all day30 scripts are syntactically valid" {
  for s in "$S"/*.sh; do
    run bash -n "$s"
    assert_success
  done
}

# ---- cost-lib ----
@test "spec_get reads fields and ignores comments" {
  printf 'name = web  # a comment\nreplicas = 4\n' >"$DIR/x.workload"
  run bash -c "source '$S/cost-lib.sh'; spec_get '$DIR/x.workload' name"
  assert_output_contains "web"
  run bash -c "source '$S/cost-lib.sh'; spec_get '$DIR/x.workload' replicas"
  assert_output_contains "4"
}

@test "workload_cost computes the expected monthly figure" {
  # 5 * (0.5 core * 0.031 + 0.5 GiB * 0.004) * 730 = 63.88
  run bash -c "source '$S/cost-lib.sh'; workload_cost 5 500 512 0.031 0.004 730"
  assert_output_contains "63.88"
}

# ---- cost-report ----
@test "cost-report lists workloads and a total" {
  run bash "$S/cost-report.sh" --dir "$DIR"
  assert_success
  assert_output_contains "frontend"
  assert_output_contains "TOTAL"
}

@test "cost-report honors custom prices and hours" {
  run bash "$S/cost-report.sh" --dir "$DIR" --cpu-price 0 --mem-price 0 --hours 730
  assert_success
  # zero prices => every cost 0.00 and total 0.00
  assert_output_contains "0.00"
}

@test "cost-report fails on an empty directory" {
  mkdir -p "$DIR/empty"
  run bash "$S/cost-report.sh" --dir "$DIR/empty"
  assert_failure
}

# ---- rightsize ----
@test "rightsize flags waste and risk, exits non-zero" {
  run bash "$S/rightsize.sh" --dir "$DIR"
  assert_failure
  assert_output_contains "WASTE"
  assert_output_contains "RISK"
  assert_output_contains "need right-sizing"
}

@test "rightsize marks a well-sized workload OK" {
  OK="$BATS_TEST_TMPDIR/ok"
  mkdir -p "$OK"
  cp "$DIR/cache.workload" "$OK/"
  run bash "$S/rightsize.sh" --dir "$OK"
  assert_success
  assert_output_contains "OK"
  assert_output_contains "all workloads right-sized"
}

@test "rightsize recommends a smaller CPU request for a wasteful workload" {
  WD="$BATS_TEST_TMPDIR/w"
  mkdir -p "$WD"
  cp "$DIR/frontend.workload" "$WD/"
  run bash "$S/rightsize.sh" --dir "$WD" --target 60
  # 100 / 0.6 = 166.6 -> 167
  assert_output_contains "167"
}

@test "rightsize reports potential savings" {
  run bash "$S/rightsize.sh" --dir "$DIR"
  assert_output_contains "Potential monthly savings"
}

@test "cost-report and rightsize require --dir" {
  run bash "$S/cost-report.sh"
  assert_failure
  run bash "$S/rightsize.sh"
  assert_failure
}
