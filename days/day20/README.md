# Day 20 — Unix Philosophy at Scale

Today's goal: stop writing monoliths. The Unix philosophy — *write programs that
do one thing well, and compose them through text streams* — is what lets small
scripts scale into real tooling. You'll build three tiny **filters** and pipe
them into a complete "top talkers" report.

---

## 📁 Scripts for today

| Script | Path | One job | — |
|---|---|---|---|
| **field** | `days/day20/scripts/field.sh` | print the Nth field of each line | filter |
| **histogram** | `days/day20/scripts/histogram.sh` | count occurrences of each stdin line | filter |
| **bar** | `days/day20/scripts/bar.sh` | render `count value` lines as ASCII bars | filter |
| **pipeline-demo** | `days/day20/scripts/pipeline-demo.sh` | composes all three into one tool | demo |

---

## 1. The rules of a good filter

1. **Do one thing.** If you can't describe it in one sentence, split it.
2. **Read stdin, write stdout.** Text is the universal interface.
3. **Diagnostics to stderr.** Never pollute the data stream with log lines.
4. **Exit codes mean something.** `0` = success; non-zero = a real problem.
5. **No surprises.** A filter is silent on empty input and never reformats data
   it wasn't asked to touch.

## 2. Compose, don't accumulate

Instead of one 300-line `analyze_logs.sh`, chain small pieces:

```bash
# top client IPs, as a bar chart — three one-job tools + pipes
field.sh 1 < access.log | histogram.sh | bar.sh
```

Each stage is independently testable, reusable, and replaceable. Want top URLs
instead? Change one number: `field.sh 2`. Want JSON? Swap the last stage.

## 3. Streams & exit codes

```bash
data  → stdout      # pipeable payload
errors → stderr      # humans & logs, never piped downstream
```

By default a pipeline's exit code is only the **last** command's. Turn on
`pipefail` so an early failure isn't masked:

```bash
set -o pipefail
badcmd | sort        # now non-zero if badcmd fails, not just if sort does
```

`pipeline-demo.sh` shows both the composed report and this exit-code lesson.

## 4. Why this scales

- **Testable:** each filter has a tiny, obvious contract (see the BATS suite).
- **Reusable:** `histogram.sh` works on *any* stream, not just logs.
- **Composable:** pipes let you build tomorrow's tool from today's parts — the
  same principle behind the CI/CD and GitOps pipelines coming in Phase 5.

---

## ✅ Verify

```bash
bats days/day20/tests
bash days/day20/scripts/pipeline-demo.sh
```

---

## Recap

| Concept | One-liner |
|---|---|
| Do one thing | small filters over monoliths |
| Text interface | read stdin, write stdout |
| Stderr | diagnostics never pollute the pipe |
| Compose | `field \| histogram \| bar` |
| Honest pipes | `set -o pipefail` |

Next up: **Day 21 — Capstone: Log Analyzer Pro** (Phase 5 begins).
