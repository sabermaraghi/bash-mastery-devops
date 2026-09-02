# Day 5 — Arguments & getopts

Today's goal: drive scripts from the command line — positional arguments, the
special parameters (`$#`, `$@`, `$0`), and proper named flags with `getopts`.
Then wire it into a real, argument-driven backup script.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Arguments** | `days/day05/scripts/arguments.sh` | Prints the script name, arg count, and every positional argument | `bash days/day05/scripts/arguments.sh alpha beta` |
| **getopts** | `days/day05/scripts/args-getopts.sh` | Parses `-e ENV`, `-v`, `-h` flags with validation and a usage message | `bash days/day05/scripts/args-getopts.sh -e prod -v` |
| **Backup** (mini-project) | `days/day05/scripts/backup.sh` | Tars a source dir into a timestamped archive, validating its inputs | `bash days/day05/scripts/backup.sh ./src ./backups` |

---

## 1. Positional arguments & special parameters

| Parameter | Meaning |
|---|---|
| `$0` | script name |
| `$1`, `$2`, ... | first, second argument |
| `$#` | number of arguments |
| `$@` | all arguments as separate quoted words (**use `"$@"`**) |
| `$*` | all arguments as a single string |

Always loop with `for arg in "$@"` (quoted) so arguments with spaces stay intact.

---

## 2. Named flags with `getopts`

```bash
while getopts ":e:vh" opt; do
  case "$opt" in
    e) env="$OPTARG" ;;   # -e takes a value (note the colon after e)
    v) verbose=true ;;    # -v is a boolean flag
    h) usage; exit 0 ;;
    :)  echo "-$OPTARG needs an argument" >&2; exit 1 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; exit 1 ;;
  esac
done
```

The leading `:` in `":e:vh"` turns on *silent* error handling so you can print
your own friendly messages.

---

## 3. Mini-project — argument-driven backup

Validate first, then act:
```bash
[[ -d "$src" ]] || { echo "Source not found: $src" >&2; exit 1; }
tar -czf "$dest/backup-$(basename "$src")-$(date +%Y%m%d-%H%M%S).tar.gz" -C "$(dirname "$src")" "$(basename "$src")"
```

---

## ✅ Verify

```bash
bats days/day05/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Positional | `$1 $2`, count `$#`, all `"$@"` |
| getopts | `while getopts ":e:vh" opt; do case ...` |
| `-x:` colon | means that flag takes a value in `$OPTARG` |
| Validate | check inputs before touching the filesystem |

Next up: **Day 6 — File I/O & redirection** (start of Phase 2).
