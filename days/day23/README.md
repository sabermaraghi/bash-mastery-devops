# Day 23 — CI/CD Framework

Today you build a small but real **pipeline engine** in pure Bash: define named
stages, run them in order, time each one, fail fast (or keep going), and print a
clean pass/fail summary. It's driven by a plain-text pipeline file — the same
shape as the YAML pipelines you already know, minus the vendor lock-in.

It reuses the course's habits: strict mode + logging (Day 11), input validation
(Day 17), and stdout-data / stderr-progress discipline (Day 20).

---

> **Two ways to run.** The **offline** default (below) runs a pipeline from a
> plain-text file — fully self-contained, no repo or tools required, and what
> CI verifies. **Option 2 (real)** runs an actual pipeline against *this git
> repo* — see the section at the bottom.

## 📁 Scripts for today

| Script | Path | What it does |
|---|---|---|
| **Pipeline lib** | `days/day23/scripts/pipeline-lib.sh` | The engine: `run_stage`, `pipeline_summary` |
| **CI runner** | `days/day23/scripts/ci-run.sh` | Executes a pipeline definition file |
| **Real CI** | `days/day23/scripts/real-ci.sh` | 🚀 Option 2 — real lint/test/secrets on your git repo |
| **Example** | `days/day23/examples/pipeline.ci` | A sample four-stage pipeline |

---

## 1. The pipeline file

One stage per line, `name = command`. Comments and blank lines are ignored:

```ini
lint    = shellcheck --severity=error days/**/scripts/*.sh
test    = bats days/**/tests
build   = echo building artifact...
publish = echo publishing...
```

## 2. Run it

```bash
bash days/day23/scripts/ci-run.sh days/day23/examples/pipeline.ci
```

```
▶ lint
  ✓ lint (0.01s)
▶ test
  ✓ test (0.01s)
...
===== pipeline summary =====
PASS  lint   0.01s
PASS  test   0.01s
PASS  build  0.01s
PASS  publish  0.01s
----------------------------
summary: 4 passed, 0 failed
```

Progress (`▶`, `✓`, `✗`) prints to **stderr**; the summary table prints to
**stdout**, so you can capture just the results: `ci-run.sh pipeline.ci >report.txt`.

## 3. Fail-fast vs keep-going

- **Default — fail-fast:** the first failing stage stops the run (exactly what
  you want gating a merge).
- **`--keep-going`:** run every stage anyway and report all failures at once
  (handy for a nightly "what's broken?" sweep).

```bash
bash days/day23/scripts/ci-run.sh --keep-going pipeline.ci
```

The runner exits non-zero if **any** stage failed — so CI blocks correctly.

## 4. Use the engine directly

`pipeline-lib.sh` is reusable on its own — no config file needed:

```bash
source days/day23/scripts/pipeline-lib.sh
run_stage "unit"  ./run-tests.sh
run_stage "smoke" curl -fsS http://localhost:8080/health
pipeline_summary
```

---

## ✅ Verify

```bash
bats days/day23/tests
bash days/day23/scripts/ci-run.sh days/day23/examples/pipeline.ci
```

---

## Recap

| Concept | One-liner |
|---|---|
| Stages | ordered `name = command` steps |
| Fail-fast | stop at first failure (default) |
| Keep-going | run all, report every failure |
| Honest exit | non-zero if any stage failed |
| Composable | summary to stdout, progress to stderr |

---

## 🚀 Option 2 — real CI pipeline (against this git repo)

The offline runner proves the *engine*. `real-ci.sh` uses that same engine to
run a real pipeline over your actual repository — the thing you'd wire into a
GitHub Actions workflow.

### What it does

1. **Scopes to your changes** — by default it lints only the shell files you
   changed vs `HEAD` (staged + unstaged). Use `--all` for every tracked script,
   `--base origin/main` for everything changed since a branch point (PR-style),
   or `--repo DIR` to point it at another checkout.
2. **Runs real stages** with the Day 23 engine:
   - **lint** — `shellcheck --severity=error`, or falls back to `bash -n` if
     shellcheck isn't installed
   - **test** — `bats -r days`
   - **secrets** — `gitleaks detect --no-git` (scans the current working tree only, not git history, so purged/old commits are never re-flagged)
3. **Degrades honestly** — a missing tool *skips* its stage with a warning and
   an install hint. It never fakes a pass, and a skip is never a failure.
4. **Speaks GitHub Actions** — when `$GITHUB_ACTIONS=true`, each stage is wrapped
   in `::group::` / `::endgroup::` and failures emit `::error::` annotations, so
   the exact same script drives a real workflow.

### Run it

```bash
# lint just what you changed (fail-fast, like a merge gate)
bash days/day23/scripts/real-ci.sh

# whole repo, run every stage even after a failure
bash days/day23/scripts/real-ci.sh --all --keep-going

# everything changed since main (PR-style)
bash days/day23/scripts/real-ci.sh --base origin/main

# point it at any other checkout
bash days/day23/scripts/real-ci.sh --all --repo /path/to/other/repo
```

### Use it in a real workflow

```yaml
# .github/workflows/ci.yml
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }   # needed for --base diffs
      - run: bash days/day23/scripts/real-ci.sh --base origin/${{ github.base_ref }}
```

### Offline vs real

| | Offline (`ci-run.sh`) | Real (`real-ci.sh`) |
|---|---|---|
| Input | a text pipeline file | your actual git repo |
| Stages | whatever you write | lint / test / secrets |
| Tools needed | none | shellcheck / bats / gitleaks (optional, skip if absent) |
| CI integration | — | GitHub Actions annotations |
| Exit codes | 0 / 1 / 2 | 0 / 1 / 2 / 3 (3 = git missing) |

---

Next up: **Day 24 — GitOps.**
