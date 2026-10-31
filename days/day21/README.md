# Day 21 — Capstone: Log Analyzer Pro

Phase 5 opens with a capstone that ties the whole course together. **Log
Analyzer Pro** ingests a web access log and produces a full report — summary
stats, top talkers, top paths, and status/method breakdowns — in a single,
fork-light pass.

It deliberately reuses everything you've built:

| From | Reused here |
|---|---|
| Day 11 | strict mode (`set -euo pipefail`) + shared logging |
| `lib/` | `logging.sh` (stderr JSON logs), `validator.sh` (`require_file`, `require_int`) |
| Day 17 | input validation before touching the filesystem |
| Day 19 | single-pass parse, associative arrays, no fork-per-line |
| Day 20 | data → stdout, diagnostics → stderr (so the report itself pipes) |

---

## 📁 Scripts for today

| Script | Path | What it does |
|---|---|---|
| **Log Analyzer Pro** | `days/day21/scripts/log-analyzer.sh` | Full access-log report |
| **Sample generator** | `days/day21/scripts/gen-sample-log.sh` | Deterministic combined-format log for demos/tests |

---

## Quick start

```bash
# generate a sample log, then analyze it
bash days/day21/scripts/gen-sample-log.sh 200 > /tmp/access.log
bash days/day21/scripts/log-analyzer.sh -n 5 /tmp/access.log
```

Example report:

```
===== Log Analyzer Pro =====
file:            /tmp/access.log
total requests:  200
malformed lines: 0
unique IPs:      3
total bytes:     99800
errors (>=400):  80
error rate:      40.0%

----- Top 5 IPs -----
67	10.0.0.1
67	10.0.0.2
66	10.0.0.3
...
```

---

## What it parses

Combined/common web log format:

```
IP - - [timestamp] "METHOD PATH PROTO" STATUS SIZE
```

- **IP** = field 1 → top talkers
- **METHOD** = field 6, **PATH** = field 7 → traffic shape
- **STATUS** = field 9 → status distribution + error rate (`>= 400`)
- **SIZE** = field 10 → total bytes served

Lines with fewer than 10 fields or a non-3-digit status are counted as
`malformed` and skipped — the analyzer never crashes on dirty input.

---

## Design notes

- **Single pass:** one `while read` over the file; four associative arrays
  accumulate counts. No `grep | sort | uniq` re-scans of the file.
- **`print_table` caps rows with `awk 'NR<=n'`, not `head`** — avoiding the
  `head` + `pipefail` SIGPIPE trap covered on Day 20.
- **Options via `getopts`** (`-n`, `-o`, `-h`) with validation borrowed from
  `lib/validator.sh`.
- **Report on stdout only**, so you can pipe it onward or `-o` it to a file.

---

## ✅ Verify

```bash
bats days/day21/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Capstone | one tool, every prior lesson |
| Single pass | assoc arrays, no re-scans |
| Robust input | malformed lines counted, never fatal |
| Composable | report to stdout, logs to stderr |

Next up: **Day 22 — Rootless containers.**
