# Day 8 — Arrays & Associative Arrays

Today's goal: store and iterate collections properly — indexed arrays,
associative arrays (maps), and `mapfile` for slurping input into an array.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Arrays** | `days/day08/scripts/arrays.sh` | Builds an indexed array, an associative map of service→port, and reads lines with `mapfile` | `bash days/day08/scripts/arrays.sh` |

---

## 1. Indexed arrays

```bash
servers=("web01" "web02")
servers+=("db01")            # append
echo "${servers[0]}"          # first
echo "${servers[-1]}"         # last
echo "${#servers[@]}"         # length
for s in "${servers[@]}"; do echo "$s"; done   # iterate (always quote!)
```

## 2. Associative arrays (maps)

Must be declared with `declare -A` first:
```bash
declare -A ports=([http]=80 [https]=443)
echo "${ports[https]}"        # value by key
for k in "${!ports[@]}"; do    # ${!map[@]} = keys
  echo "$k -> ${ports[$k]}"
done
```

## 3. `mapfile` — read into an array

Unlike a piped `while` loop, `mapfile` keeps the values after it finishes:
```bash
mapfile -t lines < <(some_command)
echo "${#lines[@]}"           # number of lines read
```

---

## ✅ Verify

```bash
bats days/day08/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Indexed | `arr=(a b)`, `arr+=(c)`, `"${arr[@]}"`, `${#arr[@]}` |
| Associative | `declare -A m`, keys `"${!m[@]}"`, value `${m[k]}` |
| Slurp | `mapfile -t arr < <(cmd)` |

Next up: **Day 9 — JSON & API integration.**
