# Day 17 — Security Fundamentals

Today's goal: write Bash that is safe to run on untrusted input and safe to
leave on disk. You'll validate with **allowlists**, avoid the classic injection
traps (`eval`, unquoted variables, predictable temp files), lock down file
permissions, and build a **dependency-free secret scanner** you can drop into CI.

> **Two ways to run this day.** **Option 1 (default)** is the offline, dependency-free
> simulation — tested by BATS and run in CI. **Option 2** runs the same idea with the
> real industry tools (`gitleaks` + `trivy`). See the [Option 2](#-option-2--real-scan-with-gitleaks--trivy)
> section below; the shared real-mode helpers live in `platform/`.

---

## 📁 Scripts for today

| Script | Path | What it does | Try it |
|---|---|---|---|
| **Security Demo** | `days/day17/scripts/security-demo.sh` | Walks through validation, quoting, safe dispatch, and secure temp files | `bash days/day17/scripts/security-demo.sh` |
| **Secret Scanner** | `days/day17/scripts/secret-scanner.sh` | Scans a tree for hardcoded credentials; exits 1 on any hit | `bash days/day17/scripts/secret-scanner.sh .` |
| **Harden Permissions** | `days/day17/scripts/harden-permissions.sh` | Writes secrets `0600` and audits a tree for weak modes | `bash days/day17/scripts/harden-permissions.sh audit .` |
| **Real Scan** _(Option 2)_ | `days/day17/scripts/real-scan.sh` | Runs real `gitleaks` + `trivy` over a path | `bash days/day17/scripts/real-scan.sh --dir .` |

---

## 1. Validate with allowlists, not blocklists

Deny by default. Enumerate what's *allowed* and reject everything else — you can
never list every bad value, but you can list the good ones.

```bash
case "$env" in
  dev | staging | prod) : ;;          # ok
  *) echo "rejected: $env" >&2; exit 1 ;;
esac
```

Reuse `lib/validator.sh` for the common cases: `require_int`, `require_safe_path`
(rejects empty, `/`, and `..` traversal), `require_file`, `require_cmd`.

## 2. Never `eval` untrusted input

`eval "$user_input"` turns data into code. Dispatch by name through a `case`
instead, so input can only ever select a predefined action:

```bash
case "$action" in
  status)  show_status ;;
  version) show_version ;;
  *) echo "unknown action" >&2; exit 1 ;;
esac
```

## 3. Quote everything

An unquoted variable is word-split on `IFS` **and** glob-expanded. `rm $file`
with `file='* '` deletes your directory. Always `"$file"`, `"$@"`, `"${arr[@]}"`.
Tightening `IFS=$'\n\t'` removes space as a splitter for extra safety.

## 4. Secure temp files

Never hardcode `/tmp/mytool.$$` — it's predictable and enables symlink attacks.
Use `mktemp`, set a restrictive `umask`, and clean up with a trap:

```bash
tmp="$(mktemp "${TMPDIR:-/tmp}/tool.XXXXXXXX")"
trap 'rm -f "$tmp"' EXIT
umask 077
```

## 5. Least-privilege file permissions

Secrets should be **owner-only**. `umask 077` makes new files `0600`; set it
explicitly with `chmod 600`. `harden-permissions.sh audit` flags world-writable
paths and secret files (`*.pem`, `*.key`, `.env`) readable by group/other.

```bash
bash days/day17/scripts/harden-permissions.sh write ./secret.txt "s3cr3t"
bash days/day17/scripts/harden-permissions.sh audit .
```

## 6. Catch secrets before they land

`secret-scanner.sh` greps for AWS keys, GitHub/Slack tokens, private-key
headers, and generic `key=...` assignments, skipping `.git` and `*.example`
templates. Exit 1 on any hit makes it CI/pre-commit ready:

```bash
bash days/day17/scripts/secret-scanner.sh .
```

---

## 🚀 Option 2 — Real scan with gitleaks + trivy

The offline `secret-scanner.sh` above is a self-contained regex engine so the
lesson runs anywhere. In the real world you'd reach for the dedicated tools it
imitates. `real-scan.sh` runs them for you:

- **gitleaks** — purpose-built secret detection (entropy + rules)
- **trivy fs** — secrets **plus** dependency vulnerabilities and misconfigurations

### Prerequisites

| Tool | Install |
|---|---|
| `gitleaks` | <https://github.com/gitleaks/gitleaks/releases> · `brew install gitleaks` |
| `trivy` | <https://aquasecurity.github.io/trivy> · `brew install trivy` |

If a required tool isn't installed, the script prints exactly what's missing and
exits `3` — it never pretends to have scanned.

### Run it

```bash
# full scan (gitleaks + trivy) over the repo
bash days/day17/scripts/real-scan.sh --dir .

# just secrets (gitleaks only — no trivy needed)
bash days/day17/scripts/real-scan.sh --dir . --secrets-only

# scan only the CURRENT files, ignoring old/inherited git history
bash days/day17/scripts/real-scan.sh --dir . --secrets-only --no-git
```

> **Old history leaks?** gitleaks scans every commit by default, so secrets that
> were committed in earlier/inherited history (even if long since removed) still
> show up. Use `--no-git` to scan just the current working tree, or allowlist
> the specific commits/paths in `.gitleaks.toml`.

Exit codes: `0` clean · `1` findings · `2` usage error · `3` a required tool is
missing. The shared helpers (`rm_require_tools`, `rm_banner`) come from
`platform/lib/realmode.sh` and are reused by every day's Option 2.

---

## ✅ Verify

```bash
bats days/day17/tests
bash days/day17/scripts/security-demo.sh
```

The Option 2 tests in `tests/real-scan.bats` automatically **skip** the
tool-dependent cases when `gitleaks`/`trivy` aren't installed, so the suite
stays green everywhere.

---

## Recap

| Concept | One-liner |
|---|---|
| Allowlist | `case "$x" in good) ;; *) reject ;; esac` |
| No eval | dispatch by name through `case` |
| Quote | `"$var"`, `"$@"`, `"${arr[@]}"` always |
| Temp files | `mktemp` + `trap rm EXIT` + `umask 077` |
| Permissions | secrets `0600`; audit for world-writable |
| Secret scan (offline) | `secret-scanner.sh` → exit 1 on any hit |
| Secret scan (real) | `real-scan.sh` → gitleaks + trivy |

Next up: **Day 18 — Zero-trust security pipeline.**
