# Day 6 — File I/O & Redirection

Today's goal: control where output goes and read files back safely — the
foundation for every script that produces a report or processes data.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **File I/O** | `days/day06/scripts/file-io.sh` | Demonstrates `>`, `>>`, here-docs, stdout/stderr redirection, and safe line-by-line reading | `bash days/day06/scripts/file-io.sh` |
| **Find Large Files** | `days/day06/scripts/find-large-files.sh` | Scans a directory for the biggest files — a practical redirection + reporting example | `bash days/day06/scripts/find-large-files.sh /var/log` |

---

## 1. Redirection operators

| Operator | Meaning |
|---|---|
| `>` | send stdout to a file (**truncates**) |
| `>>` | append stdout to a file |
| `2>` | send stderr to a file |
| `&>` | send **both** stdout and stderr |
| `<` | read stdin from a file |
| `\|` | pipe stdout of one command into another |

```bash
command >out.txt 2>err.txt      # split streams
command &>all.txt               # combine streams
command 2>/dev/null             # discard errors
```

---

## 2. Here-documents

Write a multi-line block into a file or command. Quote the delimiter (`'BLOCK'`)
to stop variable expansion:
```bash
cat >config.txt <<'BLOCK'
key=value
literal $notexpanded
BLOCK
```

---

## 3. Reading files back safely

Always `IFS= read -r` and redirect from the file (not a pipe) so your counters
survive the loop:
```bash
while IFS= read -r line; do echo "$line"; done <file.txt
```

---

## ✅ Verify

```bash
bats days/day06/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Redirect | `>` truncate, `>>` append, `2>` stderr, `&>` both |
| Here-doc | `<<'EOF' ... EOF` (quote to disable expansion) |
| Read | `while IFS= read -r line; do ... done <file` |

Next up: **Day 7 — Text processing (grep/sed/awk).**
