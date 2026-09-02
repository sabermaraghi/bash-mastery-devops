# Day 2 — Conditionals & Test Expressions

Today's goal: make decisions safely with `if/elif/else` and the `[[ ]]` test
operator, then fold that into a small script that validates its input before
trusting it.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Conditionals** | `days/day02/scripts/conditionals.sh` | Classifies an age (adult / just-18 / minor), then checks a string isn't empty | `bash days/day02/scripts/conditionals.sh` |
| **Access Checker** (mini-project) | `days/day02/scripts/access-checker.sh` | Takes a name + age, validates the age is numeric, then welcomes or denies | `bash days/day02/scripts/access-checker.sh Alice 25` |

---

## 1. The shape of a conditional

```bash
if [[ condition ]]; then
  ...
elif [[ other ]]; then
  ...
else
  ...
fi
```

Use `[[ ]]` (not the older `[ ]`) — it's safer with unquoted variables and
supports `=~` regex matching.

---

## 2. Common comparisons

| Kind | Operators |
|---|---|
| Numbers | `-eq` equal, `-ne` not-equal, `-gt` / `-lt`, `-ge` / `-le` |
| Strings | `==`, `!=`, `-n "$s"` (non-empty), `-z "$s"` (empty) |
| Regex | `[[ "$age" =~ ^[0-9]+$ ]]` (matches a whole number) |

**Script** (`scripts/conditionals.sh`):
```bash
age=25
if [[ $age -gt 18 ]]; then
  echo "You are an adult."
elif [[ $age -eq 18 ]]; then
  echo "You just became an adult."
else
  echo "You are a minor."
fi
```

---

## 3. Mini-project — Access Checker

Put it together: read a name and age from the command line, **validate** the age
is actually numeric (never trust input), then decide.

```bash
[[ "$age" =~ ^[0-9]+$ ]] || { echo "AGE must be a number"; exit 1; }
[[ $age -ge 18 ]] && echo "Welcome, $name!" || echo "Access denied."
```
**Run it:** `bash scripts/access-checker.sh Alice 25` → `Welcome, Alice!`

---

## ✅ Verify

```bash
bats days/day02/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Shape | `if [[ ... ]]; then ... elif ... else ... fi` |
| Numbers | `-eq -ne -gt -lt -ge -le` |
| Strings | `==` `!=` `-n` `-z` |
| Regex | `[[ "$v" =~ ^[0-9]+$ ]]` — validate before you trust |

Next up: **Day 3 — Loops.**
