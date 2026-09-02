# Day 24 — GitOps

GitOps flips deployment on its head: instead of *pushing* changes, you declare
the **desired state** in git and a **reconciler** continuously makes the live
world match it. Today you build that loop — reconcile + drift detection — as a
content-addressed, idempotent sync.

**Model:** `DESIRED/` (your git source of truth) → reconcile → `LIVE/` (reality).
Everything compares by SHA-256, so it's order-independent and safe to re-run.

---

## 📁 Scripts for today

| Script | Path | What it does |
|---|---|---|
| **GitOps lib** | `days/day24/scripts/gitops-lib.sh` | `list_files`, `file_hash`, `diff_state` |
| **Reconcile** | `days/day24/scripts/reconcile.sh` | Converge LIVE to DESIRED (idempotent) |
| **Drift detect** | `days/day24/scripts/drift-detect.sh` | Read-only guardrail; non-zero on drift |

---

## 1. Declare, then reconcile

```bash
# desired/ holds what SHOULD be live (rendered manifests, configs, ...)
bash days/day24/scripts/reconcile.sh desired/ live/
```

```
CREATE  app/deployment.yaml
CREATE  app/service.yaml
----------------------------
applied: 2 created, 0 updated, 0 pruned
```

Actions the reconciler takes:

| Action | When |
|---|---|
| **CREATE** | file declared in DESIRED, missing from LIVE |
| **UPDATE** | file exists in both but content drifted |
| **PRUNE** | file in LIVE not declared in DESIRED (only with `--prune`) |
| **IGNORE** | extra LIVE file, `--prune` not set |

## 2. Idempotency is the whole point

Run it again with no upstream change and nothing happens:

```
----------------------------
already in sync
```

Because state is compared by content hash — not timestamps — reconciling is safe
to run every minute, forever.

## 3. Plan before you apply

```bash
bash days/day24/scripts/reconcile.sh --dry-run --prune desired/ live/
# reports CREATE/UPDATE/PRUNE lines, then: "planned: ..." — touches nothing
```

## 4. Catch out-of-band changes

`drift-detect.sh` is read-only and exits non-zero when reality has diverged —
perfect for a cron alert or a CI gate:

```bash
bash days/day24/scripts/drift-detect.sh desired/ live/ || notify "drift!"
```

```
CHANGED	app/service.yaml
EXTRA	app/rogue.yaml
----------------------------
drift detected: 2 file(s) diverged
```

---

## Two ways to run

**Option 1 (default, offline)** is everything above: `reconcile.sh` + `drift-detect.sh`
sync one directory into another and compare by SHA-256. No cluster, no tools,
always CI-green — that's what the tests exercise.

**Option 2 (real)** runs the *same* GitOps loop against a real Kubernetes
cluster using `kubectl`. The offline default stays the default; the real path
degrades gracefully (clear message + exit 3) when the tool or cluster is absent.

### 🧰 Before you start (real-mode setup)

> **Everything below is optional.** Option 1 (offline) needs none of this. Do
> this only if you want to run against a real cluster.

**1. Install the tools** (macOS/Linux with [Homebrew](https://brew.sh)):

```bash
brew install kubectl   # talks to the cluster (apply / diff)
brew install kind      # runs a real, lightweight Kubernetes cluster locally
# git is only needed for --git-url and is almost certainly already installed
```

No brew? See the official docs: [kubectl](https://kubernetes.io/docs/tasks/tools/) ·
[kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation).

**2. Start a cluster (kind) and confirm it's running:**

```bash
# Is a cluster already up? List kind clusters:
kind get clusters                 # prints cluster names, or nothing if none

# Create one if the list was empty (takes ~30s, light enough for 8GB RAM):
kind create cluster --name bash-mastery

# Verify kubectl can reach it — this should print server version info:
kubectl cluster-info
kubectl get nodes                 # node should be STATUS=Ready
```

**3. Know your context.** kind registers a context named `kind-<clustername>`
(so `--name bash-mastery` → context `kind-bash-mastery`). Check and use it:

```bash
kubectl config current-context    # e.g. kind-bash-mastery
kubectl config get-contexts       # list every cluster you can target
```

Pass that value as `--context` so you always hit the cluster you mean (see the
examples below). Omit `--context` to use whatever `current-context` is set to.

---

### 🚀 Option 2 — real GitOps against a live cluster

> **Note:** `./manifests` in the examples is a **placeholder** — point `--dir`
> at your own folder of Kubernetes YAML. If you don't have one yet, jump to
> **"Try it end-to-end"** below, which creates a real demo manifest for you.

`days/day24/scripts/real-gitops.sh` maps the offline model onto reality:

| Offline (Option 1) | Real (Option 2) |
|---|---|
| DESIRED dir → LIVE dir | manifests dir → cluster namespace |
| `cp` on hash mismatch | `kubectl apply -f` |
| `--prune` deletes extra files | `kubectl apply --prune -l <label>` |
| `diff_state` compares hashes | `kubectl diff -f` |
| `drift-detect.sh` (read-only) | `real-gitops.sh drift` (read-only) |

**Reconcile** — make the cluster match your manifests:

```bash
# plan first (server-side dry run, changes nothing)
bash days/day24/scripts/real-gitops.sh reconcile \
  --dir ./manifests --context kind-bash-mastery --namespace demo --dry-run

# apply for real
bash days/day24/scripts/real-gitops.sh reconcile \
  --dir ./manifests --context kind-bash-mastery --namespace demo

# apply and prune objects no longer declared (label-scoped, safe)
bash days/day24/scripts/real-gitops.sh reconcile \
  --dir ./manifests --context kind-bash-mastery --namespace demo --prune
```

> Replace `kind-bash-mastery` with your own context from
> `kubectl config current-context`. Drop `--context` entirely to use the current one.

**Drift** — read-only guardrail, exits non-zero when the cluster diverged:

```bash
bash days/day24/scripts/real-gitops.sh drift \
  --dir ./manifests --context kind-bash-mastery --namespace demo \
  || notify "cluster drifted from git!"
```

**Pull straight from git** (the real GitOps "pull" model — clone, then apply):

```bash
bash days/day24/scripts/real-gitops.sh reconcile \
  --git-url https://github.com/you/your-manifests.git --git-ref main --path k8s/ \
  --namespace demo
```

**Try it end-to-end** (creates a real demo manifest — no folder of your own needed).
First set `CTX` to your context so you can copy-paste the rest as-is:

```bash
CTX="$(kubectl config current-context)"   # e.g. kind-bash-mastery

mkdir -p /tmp/gitops-demo
cat > /tmp/gitops-demo/cm.yaml <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: day24-demo
  labels:
    app.kubernetes.io/managed-by: day24-gitops
data:
  hello: "from gitops"
YAML

# reconcile the demo into the cluster, then confirm there's no drift
bash days/day24/scripts/real-gitops.sh reconcile --dir /tmp/gitops-demo --context "$CTX" --namespace default
bash days/day24/scripts/real-gitops.sh drift     --dir /tmp/gitops-demo --context "$CTX" --namespace default

# now cause drift by hand, then watch `drift` catch it (exit non-zero):
kubectl --context "$CTX" -n default patch configmap day24-demo -p '{"data":{"hello":"changed"}}'
bash days/day24/scripts/real-gitops.sh drift --dir /tmp/gitops-demo --context "$CTX" --namespace default

# reconcile again to heal it back to the git-declared state:
bash days/day24/scripts/real-gitops.sh reconcile --dir /tmp/gitops-demo --context "$CTX" --namespace default

# clean up when you're done poking at it:
kubectl --context "$CTX" -n default delete configmap day24-demo
rm -rf /tmp/gitops-demo
```

| Flag | Applies to | Meaning |
|---|---|---|
| `--dir DIR` | both | directory of manifests (source of truth) |
| `--namespace NS` | both | target namespace |
| `--context CTX` | both | kube-context (safety when you have many clusters) |
| `--git-url` / `--git-ref` / `--path` | both | clone desired state from a git remote first |
| `--dry-run` | reconcile | server-side dry run: plan only |
| `--prune` | reconcile | delete undeclared objects (label-scoped) |
| `--label SELECTOR` | reconcile | prune label (default `app.kubernetes.io/managed-by=day24-gitops`) |

**Exit codes:** `0` in-sync/applied · `1` drift detected · `2` usage · `3` missing tool or unreachable cluster (never fakes a sync).

---

## ✅ Verify

```bash
# offline (default) suite
bats days/day24/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Desired state | git is the source of truth |
| Reconcile | make LIVE match DESIRED |
| Idempotent | content hashes, safe to re-run |
| Prune | remove undeclared drift |
| Drift detect | read-only guardrail, non-zero on divergence |

Next up: **Day 25 — kubectl automation.**
