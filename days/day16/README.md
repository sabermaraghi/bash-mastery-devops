# Day 16 — Pre-commit Hooks & Linting

Today's goal: understand the quality gate that's been protecting this repo since
Day 1 — `.pre-commit-config.yaml` — and learn how to run it per day.

---

## 📁 Files for today

| File | Path | What it does |
|---|---|---|
| **Pre-commit config** | `.pre-commit-config.yaml` (repo root) | Declares every hook: shfmt, shellcheck, gitleaks, hygiene, + local trivy/bats |
| **Run Checks** | `days/day16/scripts/run-checks.sh` | The same gate as a plain script, skipping tools that aren't installed |
| **CI** | `.github/workflows/ci.yml` | Runs the identical checks on every push |

---

## 1. How pre-commit works

`pre-commit` installs a Git hook that runs configured checks **before** a commit
is created. If a hook fails (or reformats a file), the commit is blocked until
you fix/stage the changes.

```bash
pip install --user pre-commit
pre-commit install          # wire it into .git/hooks
```

## 2. Per-day runs (the workflow for this course)

Run the gate on **only the files that day changed** — never `--all-files` until
the whole course is done:
```bash
pre-commit run --files days/day16/scripts/*.sh days/day16/tests/*.bats
```

## 3. The hooks in our config

| Hook | Catches |
|---|---|
| trailing-whitespace / end-of-file-fixer | sloppy diffs |
| detect-private-key | committed secrets |
| **shfmt** (`-i 2 -ci`) | inconsistent formatting |
| **shellcheck** (`--severity=error`) | real bugs (unquoted vars, etc.) |
| **gitleaks** | secrets/tokens in history |
| trivy / bats (local) | vulns + failing tests (skip if tool absent) |

## 4. Fixing what it finds

```bash
shfmt -w -i 2 -ci path/to/script.sh    # auto-format in place
shellcheck -x path/to/script.sh         # read the SC#### codes and fix
```

---

## ✅ Verify

```bash
bats days/day16/tests
bash days/day16/scripts/run-checks.sh
```

---

## Recap

| Concept | One-liner |
|---|---|
| Install | `pre-commit install` |
| Per day | `pre-commit run --files days/dayNN/...` |
| All (final only) | `pre-commit run --all-files` |
| Same in CI | `.github/workflows/ci.yml` |

Next up: **Day 17 — Security fundamentals**.
