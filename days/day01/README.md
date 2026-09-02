# Day 1 — Shell Basics & Variables

Today's goal: get the two things every Bash script depends on right — the
boilerplate every script starts with, and how variables actually work
(including the sharp edges that bite beginners).

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Variables** | `days/day01/scripts/variables.sh` | Sets a name and age, prints them, then locks a `pi` value with `readonly` so it can't be reassigned | `bash days/day01/scripts/variables.sh` |

---

## 1. The boilerplate every script starts with

- Bash is the shell/scripting language you're already using in your terminal.
- Every script starts with a **shebang** — the first line: `#!/usr/bin/env bash`
  (preferred over `#!/bin/bash`, since bash may live elsewhere in containers).
- Right after it, add `set -euo pipefail`. This one line saves hours later:
  - `-e` → stop immediately if any command fails
  - `-u` → error if you reference a variable that was never set (catches typos)
  - `-o pipefail` → catch failures *inside* a pipe (`cmd1 | cmd2`), not just the last
- Run a script with `bash script.sh`, or `chmod +x script.sh && ./script.sh`.

---

## 2. Variables

- **Set one:** `name="Alice"` — no spaces around the `=`, or Bash reads it as a command.
- **Read one:** `$name` or `${name}`. Use the braces next to other text: `"${name}_backup"`.
- Everything is a string by default — numbers are only numbers inside `(( ))`.
- **Lock a value:** `readonly pi=3.14` — a later reassignment fails loudly.
- **Share with child processes:** `export VAR="value"`.

**Script** (`scripts/variables.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

name="Alice"
age=30
echo "Name: $name, Age: $age"

readonly pi=3.14
echo "Pi: $pi"
```
**Output:**
```
Name: Alice, Age: 30
Pi: 3.14
```

---

## ✅ Verify

```bash
bats days/day01/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Boilerplate | `#!/usr/bin/env bash` + `set -euo pipefail` on every script |
| Set / read | `name="value"` (no spaces), read with `$name` / `${name}` |
| Lock | `readonly pi=3.14` prevents reassignment |
| Export | `export VAR` shares a value with child processes |

Next up: **Day 2 — Conditionals & test expressions.**
