# Day 11 — Error Handling, Logging & Debugging

Today's goal: make scripts fail *safely and loudly*. Strict mode, `trap` for
cleanup and error reporting, the shared structured logger, and the debugging
flags that show you exactly what ran.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Error Handling** (demo) | `days/day11/scripts/error-handling.sh` | Shows strict mode + `EXIT`/`ERR` traps + `lib/logging.sh` on a small example | `bash days/day11/scripts/error-handling.sh` |
| **Robust Backup** | `days/day11/scripts/robust-backup.sh` | Production backup with validation, retries, and cleanup traps | see script header |
| **Deploy with Rollback** | `days/day11/scripts/deploy-with-rollback.sh` | Deploys and automatically rolls back on failure | see script header |
| **Secure Config Loader** | `days/day11/scripts/secure-config-loader.sh` | Hardened config loading | see script header |
| **Cleanup with Lock** | `days/day11/scripts/cleanup-with-lock.sh` | Single-instance cleanup guarded by `flock` | see script header |
| **DB Backup/Restore** | `days/day11/scripts/database-backup-restore.sh` | Backup + restore with error handling | see script header |
| **Health Check Monitor** | `days/day11/scripts/health-check-monitor.sh` | Retrying health probe | see script header |

---

## 1. Strict mode (already on every script)

`set -euo pipefail` — exit on error, error on unset vars, catch pipe failures.
Add `shopt -s inherit_errexit` so `-e` also applies inside command substitutions.

## 2. Traps — run code on exit or error

```bash
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT                    # always runs, success or failure
trap 'echo "failed at line $LINENO" >&2' ERR
```

## 3. Structured logging (shared)

Source the one logger — never re-implement it:
```bash
source "$REPO_ROOT/lib/logging.sh"
log_info "starting"; log_error "boom"
```

## 4. Debugging

```bash
bash -x script.sh        # trace every command
bash -n script.sh        # syntax check without running (used by our tests)
set -x; ...; set +x      # trace just a section
```

---

## ✅ Verify

```bash
bats days/day11/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Strict mode | `set -euo pipefail` (+ `inherit_errexit`) |
| Traps | `trap cleanup EXIT`, `trap '... $LINENO' ERR` |
| Logging | `source lib/logging.sh`; `log_info/warn/error` |
| Debug | `bash -x` trace, `bash -n` syntax check |

Next up: **Day 12 — Process management & signals.**
