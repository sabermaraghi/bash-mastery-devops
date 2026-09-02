# Day 15 — Unit Testing with BATS

Today's goal: make BATS a first-class habit. You've *seen* a `tests/` suite in
every day so far — today you learn exactly how they work and how to write your own.

---

## 📁 Files for today

| File | Path | What it does |
|---|---|---|
| **Calc** | `days/day15/scripts/calc.sh` | A tiny `add` / `divide` library, testable and CLI-runnable |
| **Calc tests** | `days/day15/tests/calc.bats` | Full BATS suite: success, integer math, failure path, CLI |
| **Shared helper** | `tests/test_helper.bash` | Resolves `REPO_ROOT` and provides `assert_success` / `assert_failure` / `assert_output_contains` |

---

## 1. Anatomy of a BATS test

```bash
#!/usr/bin/env bats
load ../../../tests/test_helper     # shared setup + assertions

setup()    { source "$REPO_ROOT/days/day15/scripts/calc.sh"; }   # per-test
teardown() { :; }                                                # per-test cleanup

@test "add sums two numbers" {
  run add 2 3        # run captures $status and $output
  assert_success     # $status == 0
  [ "$output" -eq 5 ]
}
```

- `run cmd` → populates `$status` (exit code) and `$output` (combined output).
- `setup`/`teardown` run **before/after every** `@test`.
- `$BATS_TEST_TMPDIR` is a fresh temp dir per test — use it, never the repo.

## 2. Testing failure paths

Don't only test the happy path. Assert that bad input **fails loudly**:
```bash
@test "divide by zero fails" {
  run divide 1 0
  assert_failure
  assert_output_contains "division by zero"
}
```

## 3. Making code testable

The source/execute guard (`[[ "${BASH_SOURCE[0]}" == "$0" ]]`) lets a suite
`source` your script to test functions directly, without side effects.

## 4. Running suites

```bash
bats days/day15/tests      # one day
bats -r days               # every day, recursively (what CI runs)
```

> No external plugins required — our `tests/test_helper.bash` ships minimal
> assertions, so suites run even where `bats-assert` isn't installed.

---

## ✅ Verify

```bash
bats days/day15/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Run | `run cmd` → `$status`, `$output` |
| Lifecycle | `setup` / `teardown` per `@test` |
| Temp | `$BATS_TEST_TMPDIR` per test |
| Failure paths | `assert_failure` + message check |
| All | `bats -r days` |

Next up: **Day 16 — Pre-commit hooks & linting.**
