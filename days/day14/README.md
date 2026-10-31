# Day 14 — Modular Libraries

Today's goal: stop copy-pasting. Everything you built in Days 11–13 (logging,
retry, locking, validation) lives once in `/lib`; today you compose a real
module from those shared building blocks.

---

## 📁 Files for today

| File | Path | What it does |
|---|---|---|
| **Shared libraries** | `lib/logging.sh`, `lib/retry.sh`, `lib/lock.sh`, `lib/validator.sh`, `lib/utils.sh` | The single source of truth for cross-cutting helpers |
| **Backup Manager** (module) | `days/day14/scripts/backup-manager.sh` | A real backup module built *only* from `/lib` — no re-implemented helpers |

---

## 1. Why one shared `/lib`

The old course had **two** loggers and **two** retry loops (one under `day6`,
one under `day10`) that drifted apart. The fix: one `/lib`, sourced everywhere.
Bug fixed once = fixed everywhere.

## 2. Sourcing a library correctly

Resolve paths from the script's own location, never the working directory:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/lib/logging.sh"
source "$REPO_ROOT/lib/retry.sh"
source "$REPO_ROOT/lib/validator.sh"
```

## 3. The source/execute guard

So a module can be both **run** and **tested** (sourced) without side effects:
```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  backup "$@"     # only when executed directly
fi
```
That guard is what lets `backup-manager.bats` source the file and call `backup()`
directly.

## 4. Library design rules

- A library is **sourced, never executed** — no top-level side effects.
- Prefix/namespace shared state; declare function-locals with `local`.
- Keep each lib single-purpose (logging vs. retry vs. validation).

---

## ✅ Verify

```bash
bats days/day14/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| One source of truth | all helpers live in `/lib` |
| Source safely | resolve via `BASH_SOURCE`, not `cwd` |
| Dual-use guard | `[[ "${BASH_SOURCE[0]}" == "$0" ]]` |
| No side effects | libraries are sourced, not run |

Next up: **Day 15 — Unit testing with BATS.**
