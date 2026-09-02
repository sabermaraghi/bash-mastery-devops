# Day 7 — Text Processing (grep / sed / awk)

Today's goal: the three tools that turn raw logs and files into answers —
`grep` (find), `sed` (edit), `awk` (compute) — plus the `cut | sort | uniq -c`
combo you'll reach for constantly.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Text Demo** | `days/day07/scripts/text-demo.sh` | Runs grep/awk/cut/sort/uniq/sed against a built-in CSV fixture | `bash days/day07/scripts/text-demo.sh` |
| **Log Analyzer** | `days/day07/scripts/log-analyzer.sh` | Real-world report of failed logins + top error keywords (auto-detects auth.log/secure/journalctl) | `bash days/day07/scripts/log-analyzer.sh` |
| **User Report** | `days/day07/scripts/user-report.sh` | Summarizes system users | `bash days/day07/scripts/user-report.sh` |
| **Nginx Top IPs** | `days/day07/scripts/nginx-access-top-ips.sh` | Ranks the busiest client IPs in an access log | `bash days/day07/scripts/nginx-access-top-ips.sh` |
| **Backup Cleaner** | `days/day07/scripts/backup-cleaner.sh` | Prunes old backups by pattern/age | `bash days/day07/scripts/backup-cleaner.sh` |

---

## 1. `grep` — find lines

```bash
grep 'ERROR' app.log            # matching lines
grep -i 'error' app.log         # case-insensitive
grep -E '(error|warn|fail)' f   # extended regex
grep -c 'ERROR' app.log         # count matches
```

## 2. `sed` — stream edit

```bash
sed 's/foo/bar/'      f   # replace first foo per line
sed -E 's/,(a|b),/,x,/' f # extended regex groups
sed -n '10,20p'       f   # print only lines 10-20
```

## 3. `awk` — columns & math

```bash
awk -F, '{ sum += $3 } END { print sum }' f   # sum a column
awk '$2 == "admin"' f                          # filter by field
```

## 4. The counting combo

```bash
cut -d, -f1 f | sort | uniq -c | sort -nr   # frequency, most common first
```

---

## ✅ Verify

```bash
bats days/day07/tests
```

---

## Recap

| Tool | Use it for |
|---|---|
| grep | finding lines (`-i`, `-E`, `-c`, `-v`) |
| sed | substituting / extracting lines |
| awk | field math and column logic |
| cut\|sort\|uniq -c | frequency tables |

Next up: **Day 8 — Arrays & associative arrays.**
