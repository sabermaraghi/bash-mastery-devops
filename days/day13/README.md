# Day 13 — Parallel & Concurrent Execution

Today's goal: speed up independent work by running it concurrently — while
*bounding* the fan-out so you don't fork-bomb the box — then collect the results.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Parallel Demo** | `days/day13/scripts/parallel-demo.sh` | Processes a list concurrently with a capped worker pool and result collection | `bash days/day13/scripts/parallel-demo.sh` |
| **Multi-Host Pinger** | `days/day13/scripts/multi-host-pinger.sh` | Pings many hosts in parallel | see header |
| **k8s Pod Cleaner** | `days/day13/scripts/k8s-pod-cleaner.sh` | Cleans completed/failed pods across namespaces | see header |
| **Docker Image Pruner** | `days/day13/scripts/docker-image-pruner.sh` | Prunes dangling/old images | see header |
| **GitHub Repo Backup** | `days/day13/scripts/github-repo-backup.sh` | Clones/archives many repos concurrently | see header |
| **Config Validator** | `days/day13/scripts/config-validator.sh` | Validates many config files in parallel | see header |
| **Cloud Cost Analyzer** | `days/day13/scripts/cloud-cost-analyzer.sh` | Aggregates cost data | see header |

---

## 1. The bounded worker pool

Unbounded `for x in ...; do work & done` can launch thousands of jobs at once.
Cap it:
```bash
MAX_PARALLEL=4; running=0
for item in "${items[@]}"; do
  work "$item" &
  ((++running >= MAX_PARALLEL)) && { wait -n; ((running--)); }
done
wait   # drain the rest
```
`wait -n` returns as soon as *any one* job finishes, freeing a slot.

## 2. Collecting results safely

Background jobs can't set variables in the parent. Append to a temp file (each
line is atomic for small writes) or a per-job file, then read after `wait`.

## 3. `xargs -P` — the quick alternative

```bash
printf '%s\n' "${items[@]}" | xargs -P 4 -I{} ./work.sh {}
```

---

## ✅ Verify

```bash
bats days/day13/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Fan-out | `work & ` in a loop |
| Bound it | `wait -n` to keep only N running |
| Drain | bare `wait` at the end |
| Collect | append to temp files, read after `wait` |
| Shortcut | `xargs -P N` |

Next up: **Day 14 — Modular libraries.**
