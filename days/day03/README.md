# Day 3 — Loops

Today's goal: master the three loop types (`for`, `while`, `until`) and the one
safe pattern for reading input line by line.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Loops** | `days/day03/scripts/loops.sh` | Runs every loop type: a list, a file glob, a C-style counter, a `while` counter, line-by-line reading, and an `until` timer | `bash days/day03/scripts/loops.sh` |

---

## 1. `for` loops

```bash
for fruit in apple banana cherry; do echo "I like $fruit"; done   # list
for f in "$DIR"/*.sh; do echo "$f"; done                          # files
for ((i = 1; i <= 5; i++)); do echo "Count: $i"; done             # counter
```

---

## 2. `while` & `until`

```bash
count=1
while [[ $count -le 3 ]]; do echo "$count"; ((count++)); done

seconds=0
until [[ $seconds -ge 3 ]]; do echo "$seconds"; ((seconds++)); done   # opposite of while
```

**Read a stream line by line** — `IFS= read -r` is *the* safe pattern; it stops
Bash trimming whitespace or mangling backslashes:
```bash
while IFS= read -r line; do
  echo "Line: $line"
done < file.txt
```

> Note: piping into a `while` runs it in a subshell, so variables set inside
> won't survive after the loop. When you need them later, redirect from a file
> (`done < file`) or use `mapfile` (Day 8).

---

## ✅ Verify

```bash
bats days/day03/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| for | `for x in list; do ... done`, or `for ((i=1;i<=n;i++))` |
| while / until | `while` runs *while* true; `until` runs *until* true |
| Safe read | `while IFS= read -r line; do ... done < file` |

Next up: **Day 4 — Functions & scope.**
