# Day 12 — Process Management & Signals

Today's goal: run work in the background, track it by PID, wait on it, and react
to signals (Ctrl-C, `kill`) cleanly instead of leaving orphans behind.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Signals Demo** | `days/day12/scripts/signals-demo.sh` | Launches background workers, captures PIDs, `wait`s, and traps `INT`/`TERM` | `bash days/day12/scripts/signals-demo.sh` |
| **Monitor** | `days/day12/scripts/monitor.sh` | Long-running system monitor with clean signal-driven shutdown | `bash days/day12/scripts/monitor.sh` |

---

## 1. Background jobs & PIDs

```bash
long_task &        # run in background
pid=$!             # PID of the last background job
jobs -l            # list background jobs
wait "$pid"         # block until it finishes
wait               # wait for ALL background jobs
```

## 2. Signals & traps

| Signal | Meaning | Typical use |
|---|---|---|
| `INT` | Ctrl-C | graceful stop |
| `TERM` | `kill` default | graceful stop |
| `KILL` | `kill -9` | cannot be trapped |
| `HUP` | terminal closed | reload config |

```bash
cleanup() { echo "shutting down"; kill 0; exit 0; }
trap cleanup INT TERM
```

## 3. Managing other processes

```bash
pgrep -f myapp            # find PIDs by name
kill -TERM "$pid"          # ask nicely
kill -0 "$pid" 2>/dev/null # is it still alive?
```

---

## ✅ Verify

```bash
bats days/day12/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Background | `cmd &`, PID in `$!` |
| Wait | `wait "$pid"` or bare `wait` |
| Signals | `trap cleanup INT TERM` |
| Inspect | `pgrep`, `kill -0`, `kill -TERM` |

Next up: **Day 13 — Parallel & concurrent execution.**
