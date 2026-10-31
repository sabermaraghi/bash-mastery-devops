# Day 25 — kubectl Automation

`kubectl` is a loaded gun: one wrong `--context` and you've applied a change to
production. Today you build **safe wrappers** that make the dangerous defaults
safe — explicit targeting, dry-run first, and hard stops on protected clusters.

The client binary is resolved via `$KUBECTL` (default `kubectl`), so these
scripts are testable with a stub and work with `oc`, pinned versions, etc.

---

## 📁 Scripts for today

| Script | Path | What it does |
|---|---|---|
| **kubectl lib** | `days/day25/scripts/kubectl-lib.sh` | `current_context`, `is_protected_context`, `is_valid_namespace` |
| **Safe apply** | `days/day25/scripts/k-apply.sh` | `kubectl apply` with rails: dry-run default, prod guard |
| **Context guard** | `days/day25/scripts/context-guard.sh` | Assert the current cluster before risky ops |

---

## 1. Never trust the current context

The #1 kubectl footgun is running against whatever cluster happens to be
selected. `k-apply.sh` **requires** explicit targeting — no `--context`/
`--namespace`, no run:

```bash
bash days/day25/scripts/k-apply.sh --context staging --namespace web app.yaml
# kubectl --context staging --namespace web apply -f app.yaml --dry-run=server
```

## 2. Dry-run by default

Without `--apply`, nothing changes — it's a server-side dry-run. You opt *in* to
real mutations:

```bash
# preview (safe)
bash days/day25/scripts/k-apply.sh --context staging --namespace web app.yaml
# actually apply
bash days/day25/scripts/k-apply.sh --context staging --namespace web --apply app.yaml
```

## 3. Protected clusters need a password, basically

Contexts matching `$PROTECTED_CONTEXTS` (default `prod,production`) are refused
unless you add `--confirm`:

```bash
bash days/day25/scripts/k-apply.sh --context prod-eu --namespace web --apply app.yaml
# ERROR: refusing to target protected context 'prod-eu' without --confirm
bash days/day25/scripts/k-apply.sh --context prod-eu --namespace web --apply --confirm app.yaml
```

## 4. Guard risky automation

Gate any destructive script behind the current-context check:

```bash
context-guard.sh staging-cluster && ./rollout-restart.sh
```

```
context MISMATCH: current='prod-cluster' expected='staging-cluster'   # exit 1
```

---

## Two ways to run

**Option 1 (default, offline)** is everything above: `k-apply.sh`,
`context-guard.sh`, and `kubectl-lib.sh` proven with a **stub `kubectl`** — no
cluster, no tools, always CI-green. That's what the tests exercise.

**Option 2 (real)** runs those *same* safety rails against a real Kubernetes
cluster. It **reuses the offline helpers** (`is_protected_context`,
`is_valid_namespace`, `current_context`), so the guarantees are identical; only
the target changes from a stub to a live API server. The offline default stays
the default; the real path degrades gracefully (clear message + exit 3) when the
tool or cluster is absent.

### 🧰 Before you start (real-mode setup)

> Optional — only needed for Option 2. Uses [Homebrew](https://brew.sh):

```bash
brew install kubectl kind    # kind runs a real, lightweight cluster locally
```

No brew? See [kubectl](https://kubernetes.io/docs/tasks/tools/) ·
[kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation).

**Get a cluster with the shared bootstrapper** (new today, used by every cluster
day 25–30). It creates a kind cluster (idempotent), optionally installs
metrics-server, and prints the context on stdout so you can capture it:

```bash
# create (or reuse) a local cluster; prints its context, e.g. kind-bash-mastery
CTX="$(bash platform/bootstrap.sh up)"

bash platform/bootstrap.sh status         # clusters / nodes / current context
bash platform/bootstrap.sh up --metrics   # also install metrics-server (Day 30)
bash platform/bootstrap.sh down           # tear it all down when finished
```

> **kind *is* real Kubernetes** (a conformant cluster inside Docker) — light
> enough for an 8 GB laptop, yet the same commands work on EKS/GKE/AKS/on-prem
> by pointing `--context` at a bigger cluster. Nothing here is kind-specific
> beyond `up`/`down`.

### 🚀 Option 2 — safe kubectl automation against a live cluster

`days/day25/scripts/real-kubectl.sh` maps the offline rails onto reality:

| Offline (Option 1) | Real (Option 2) |
|---|---|
| `k-apply.sh` against a stub | `real-kubectl.sh apply` against the cluster |
| dry-run default | `--dry-run=server` unless `--apply` |
| protected-context guard | same guard, real `kubectl apply` |
| `context-guard.sh` | `real-kubectl.sh guard EXPECTED` |
| (n/a) | `real-kubectl.sh get` — read-only inspection |

**Safe apply** — explicit targeting, server dry-run by default:

```bash
# preview (safe: server-side dry-run, changes nothing)
bash days/day25/scripts/real-kubectl.sh apply --context "$CTX" --namespace demo app.yaml

# actually apply
bash days/day25/scripts/real-kubectl.sh apply --context "$CTX" --namespace demo --apply app.yaml

# protected contexts (prod-like) refuse to mutate without --confirm
bash days/day25/scripts/real-kubectl.sh apply --context prod-eu --namespace demo --apply --confirm app.yaml
```

**Guard** — assert the live cluster before risky automation:

```bash
bash days/day25/scripts/real-kubectl.sh guard "$CTX" && ./rollout-restart.sh
```

**Get** — read-only inspection (never mutates):

```bash
bash days/day25/scripts/real-kubectl.sh get --context "$CTX" --namespace demo pods deployments
```

**Try it end-to-end on your kind cluster:**

```bash
CTX="$(bash platform/bootstrap.sh up)"      # ensure a cluster exists
kubectl --context "$CTX" create namespace demo --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -

cat > /tmp/cm.yaml <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: day25-demo
data:
  hello: "from day25"
YAML

bash days/day25/scripts/real-kubectl.sh apply --context "$CTX" --namespace demo /tmp/cm.yaml          # dry-run
bash days/day25/scripts/real-kubectl.sh apply --context "$CTX" --namespace demo --apply /tmp/cm.yaml   # live
bash days/day25/scripts/real-kubectl.sh get   --context "$CTX" --namespace demo configmaps
bash days/day25/scripts/real-kubectl.sh guard "$CTX"                                                  # context OK

# clean up when done (--wait=false returns immediately; namespace terminates
# in the background instead of blocking the shell while finalizers run):
kubectl --context "$CTX" delete namespace demo --wait=false
rm -f /tmp/cm.yaml
```

| Flag / arg | Subcommand | Meaning |
|---|---|---|
| `--context CTX` | apply / get | kube-context to target (required) |
| `--namespace NS` | apply / get | target namespace (required, validated) |
| `--apply` | apply | opt in to a real mutation (default is dry-run) |
| `--confirm` | apply | required to touch a protected context |
| `EXPECTED` | guard | context the current one must equal |
| `RESOURCE...` | get | resources to list (default `pods`) |

**Exit codes:** `0` ok · `1` guard mismatch / apply failure · `2` usage · `3`
missing tool or unreachable cluster (never fakes a change).

---

## ✅ Verify

```bash
bats days/day25/tests        # offline + real (stubbed kubectl)
bats platform/tests          # the shared bootstrapper (stubbed kind/kubectl)
```

> Both real suites inject **stub `kubectl`/`kind`** via `$KUBECTL`/`$KIND`, so
> they exercise every guard and the cluster lifecycle with no real cluster.

---

## Recap

| Concept | One-liner |
|---|---|
| Explicit targeting | `--context` + `--namespace` required |
| Safe default | server-side dry-run unless `--apply` |
| Prod guard | protected contexts need `--confirm` |
| Context guard | verify the cluster before acting |
| Swappable client | `$KUBECTL` for stubs/versions |

Next up: **Day 26 — Kubernetes Operators & CRDs.**
