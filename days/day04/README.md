# Day 4 — Functions & Scope

Today's goal: write functions the safe way — `local` variables, echo-to-return,
default arguments, and the array-return pattern.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Functions** | `days/day04/scripts/functions.sh` | Defines four functions: a greeting with a timestamp, an adder that returns a value, a backup helper with defaults, and one that fills a global array | `bash days/day04/scripts/functions.sh` |

---

## 1. The rules that keep functions safe

- Declare every variable inside a function as `local` — otherwise it leaks into
  the rest of the script and can silently overwrite something.
- Bash's `return` only returns a **numeric exit code**, not data. To "return" a
  value, `echo` it and capture with `$(...)`.

```bash
add() { local a=$1 b=$2; echo $((a + b)); }
result=$(add 15 27)   # 42
```

---

## 2. Default arguments

`${1:-/home}` means "use arg 1, or `/home` if nothing was passed":
```bash
backup() { local src="${1:-/home}" dest="${2:-/backup}"; echo "$src -> $dest"; }
```

---

## 3. Returning multiple values

Bash functions can't return arrays directly — build the array inside and assign
it to a global at the end:
```bash
get_system_info() {
  local info=(); info+=("user:$(whoami)"); info+=("host:$(hostname)")
  SYSTEM_INFO=("${info[@]}")
}
```

---

## ✅ Verify

```bash
bats days/day04/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Scope | Always `local` inside functions |
| Return data | `echo` + `$(func)` (not `return`, which is a number) |
| Defaults | `${1:-default}` |
| Arrays out | build locally, assign to a global at the end |

Next up: **Day 5 — Arguments & getopts.**
