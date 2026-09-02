# Day 9 — JSON & API Integration

Today's goal: read, filter, and build JSON with `jq` — the lingua franca of
every REST API, cloud CLI, and structured log you'll touch in DevOps.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **JSON Demo** | `days/day09/scripts/json-demo.sh` | Parses names, filters admins, and builds a new JSON object with `jq` (skips cleanly if jq isn't installed) | `bash days/day09/scripts/json-demo.sh` |
| **JSON Log Parser** | `days/day09/scripts/json-log-parser.sh` | Aggregates a large JSON log in a single `jq` pass (error/warn counts, top IPs) | `bash days/day09/scripts/json-log-parser.sh` |

---

## 1. Reading JSON with `jq`

```bash
jq -r '.users[].name'                       # -r = raw (no quotes)
jq -r '.users[] | select(.role=="admin")'   # filter
jq '.items | length'                        # aggregate
```

## 2. Building JSON

```bash
jq -n --arg host "api.example.com" '{endpoint:$host, ok:true}'
```
Use `--arg` / `--argjson` to inject shell values safely (never string-concatenate
into JSON).

## 3. Talking to an API

```bash
curl -fsS -H "Authorization: Bearer $API_KEY" "https://$TARGET_HOST/v1/status" \
  | jq -r '.status'
```
`-f` fails on HTTP errors, `-s` is silent, `-S` still shows errors.

## 4. Performance note

When processing many lines, make **one** `jq -s` pass over the whole set instead
of invoking `jq` per line — that's the fix baked into `json-log-parser.sh`.

---

## ✅ Verify

```bash
bats days/day09/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Read | `jq -r '.a.b[]'` |
| Filter | `select(.role=="admin")` |
| Build | `jq -n --arg x "$v" '{k:$x}'` |
| API | `curl -fsS -H "Authorization: Bearer $KEY" ... \| jq` |

Next up: **Day 10 — Environment variables & config.**
