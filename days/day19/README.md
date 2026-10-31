# Day 19 — Performance & Optimization

Today's goal: make Bash *fast*. The single biggest win is understanding that
**every external command is a fork + exec** — cheap once, brutal inside a hot
loop. You'll measure with a real benchmark harness, then rewrite slow patterns
using builtins, `mapfile`, and `[[ ]]`.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Bench** | `days/day19/scripts/bench.sh` | Micro-benchmark harness (CLI or sourced) | `bash days/day19/scripts/bench.sh 1000 sleep-test true` |
| **Optimize Demo** | `days/day19/scripts/optimize-demo.sh` | Slow-vs-fast, measured side by side | `bash days/day19/scripts/optimize-demo.sh` |
| **Log Tally** | `days/day19/scripts/log-tally.sh` | Fast single-pass field frequency counter | `bash days/day19/scripts/log-tally.sh access.log 1 10` |

---

## 1. The golden rule: avoid forks in hot loops

```bash
# SLOW — two forks per iteration
upper=$(echo "$s" | tr '[:lower:]' '[:upper:]')
# FAST — zero forks, pure builtin
upper="${s^^}"
```

Other common offenders and their built-in replacements:

| Slow (forks) | Fast (builtin) |
|---|---|
| `basename "$p"` | `"${p##*/}"` |
| `dirname "$p"` | `"${p%/*}"` |
| `echo "$x" \| sed 's/a/b/'` | `"${x/a/b}"` |
| `expr $a + $b` | `$((a + b))` |
| `cat f \| grep x` | `grep x f` |
| `wc -l < f` (in a loop) | `mapfile` once, use `${#arr[@]}` |

## 2. Measure, don't guess

`bench.sh` runs a command N times and reports total + average. It prefers bash
5's fork-free `EPOCHREALTIME` and falls back to `date`:

```bash
source days/day19/scripts/bench.sh
bench 5000 "builtin upper"  my_fast_fn
bench 5000 "fork echo|tr"   my_slow_fn
```

Run `optimize-demo.sh` to see three head-to-head comparisons measured live.

## 3. `mapfile` for bulk reads

A `while read` loop calls `read` once per line; `mapfile` slurps the whole file
in one shot:

```bash
mapfile -t lines < big.txt      # array of lines
echo "${#lines[@]}"             # line count, no `wc` fork
```

## 4. Real tool: single-pass tally

`log-tally.sh` replaces the classic `awk/cut | sort | uniq -c | sort -rn`
pipeline with **one pass** and an associative array — no fork per line, and you
keep full control in-shell:

```bash
bash days/day19/scripts/log-tally.sh access.log 1 10   # top 10 client IPs
```

---

## ✅ Verify

```bash
bats days/day19/tests
bash days/day19/scripts/optimize-demo.sh 500
```

---

## Recap

| Concept | One-liner |
|---|---|
| Forks are costly | prefer builtins in hot loops |
| Parameter expansion | `${s^^}`, `${p##*/}`, `${x/a/b}` |
| Bulk read | `mapfile -t arr < file` |
| Measure | `bench <iters> <label> <cmd>` |
| Single-pass tally | assoc array beats `sort \| uniq -c` |

Next up: **Day 20 — Unix philosophy at scale.**
