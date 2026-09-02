# Day 27 — ArgoCD App-of-Apps

ArgoCD watches git and syncs each **Application** into the cluster. The
*app-of-apps* pattern takes it one level up: a single **root** Application
declares a directory of child apps, so your whole platform bootstraps from one
entry point — all declarative, all in git.

Today you build that in shell: leaf apps that sync a source dir → dest dir
(Day 24's engine), and a root app that fans out to its children (Day 26's
declarative model). No real ArgoCD needed.

---

## 📁 Scripts for today

| Script | Path | What it does |
|---|---|---|
| **Argo lib** | `days/day27/scripts/argo-lib.sh` | `app_get`, `diff_dirs`, hashing |
| **Sync app** | `days/day27/scripts/sync-app.sh` | Sync one leaf Application (source → dest) |
| **Sync root** | `days/day27/scripts/sync-root.sh` | App-of-apps: sync every child |
| **Real (Option 2)** | `days/day27/scripts/real-argo.sh` | Real ArgoCD on a live cluster (see below) |

> The example manifests under `days/day27/examples/desired/<app>/` are **real
> Kubernetes YAML** (Deployment + Service). Offline mode just hashes/copies
> them; real ArgoCD applies them to the cluster. Same files, both modes.

---

## 1. A leaf Application

```ini
kind   = Application
name   = frontend
source = days/day27/examples/desired/frontend   # git (desired)
dest   = /tmp/argo-demo/frontend                # live
```

```bash
bash days/day27/scripts/sync-app.sh --app days/day27/examples/apps/frontend.app --base "$PWD"
```

```
CREATE	deployment.yaml
----------------------------
app frontend: Synced (Healthy)
```

Sync status is honest: **Synced/OutOfSync** plus **Healthy/Degraded**, computed
by re-diffing after apply. Unmanaged extra files are left alone unless `--prune`.

## 2. The root: app-of-apps

```ini
kind = Application
name = platform-root
apps = days/day27/examples/apps      # a dir of child *.app manifests
```

```bash
bash days/day27/scripts/sync-root.sh --app days/day27/examples/root.app --base "$PWD"
```

```
>>> syncing api.app
app api: Synced (Healthy)
>>> syncing frontend.app
app frontend: Synced (Healthy)
============================
root platform-root: 2/2 apps synced
```

Add a new service by dropping one `*.app` file in the apps dir and committing —
the next root sync picks it up. That's the whole point of app-of-apps.

## 3. Dry-run as a fleet gate

`--dry-run` reports what *would* change and exits non-zero when anything is
OutOfSync — so `sync-root --dry-run` is a CI gate for your entire platform:

```bash
bash days/day27/scripts/sync-root.sh --app root.app --base "$PWD" --dry-run || echo "drift!"
```

| Flag | Effect |
|---|---|
| `--dry-run` | plan only; non-zero if OutOfSync |
| `--prune` | delete live files not declared in git |
| `--base DIR` | resolve manifest paths against DIR |

---

## Two ways to run

**Option 1 (default, offline)** is everything above: leaf apps and the
app-of-apps root, reconciled by hashing dirs — no ArgoCD, no cluster, always
CI-green.

**Option 2 (real)** drives the genuine GitOps control plane: **real ArgoCD**
installed in the cluster, with our `.app` manifests translated into real ArgoCD
`Application` CRs. It **reuses the offline parser** (`argo-lib.sh`: `app_get`)
and the **Day 25 kubectl safety rails** (`kubectl-lib.sh`), and the same
app-of-apps idea maps 1:1: a root Application whose `path` is a directory of
child Applications.

### 🚀 Option 2 — real ArgoCD on a live cluster

Setup is the Day 25 cluster (`brew install kubectl kind`, then
`CTX="$(bash platform/bootstrap.sh up)"`). Optionally `brew install argocd` for
the CLI — **you don't need it**: `sync`/`status` use kubectl by default, so no
`argocd login` is required (pass `--use-cli` only if you want the CLI).

| Offline (Option 1) | Real (Option 2) |
|---|---|
| `.app` manifest | `real-argo.sh render` → a real `Application` CR |
| `sync-app.sh` (leaf) | an `Application` with `path = source` |
| `sync-root.sh` (app-of-apps) | a root `Application` with `path = a dir of child Applications` |
| hash-diff "sync" | `real-argo.sh sync` (kubectl refresh; `--use-cli` for argocd) |
| dry-run gate | `--dry-run=server` unless `--apply` |

> ArgoCD pulls from **git**, so real mode needs your repo URL. The `.app`'s
> `source`/`apps` becomes the `path` inside `--repo-url`.

#### About that `REPO=...` — do you need a separate repo?

**No.** `REPO` is just *this* repo's git URL — the one you already push to:

```bash
REPO="https://github.com/<you>/bash-mastery-devops.git"
```

ArgoCD runs **inside the cluster** and clones that URL to read the manifests, so
it only needs to be reachable from the cluster: **public repo = nothing to do;
private repo = add repo credentials in the ArgoCD UI once.** A dedicated GitOps
repo is a nice production pattern but is **not required** for this day. And no —
we use **plain YAML** directory sources, so there is **no Helm** here (the old
repo had none either); Helm/Kustomize are just other ArgoCD source types we
simply don't use.

> **The flow at a glance:** Step 1 installs ArgoCD (once). Step 2 is an
> *optional* UI viewer that runs in its own terminal. Step 3 deploys your apps —
> pick **one** of two paths. You never Ctrl+C to move between steps; the only
> thing that "blocks" on purpose is the Step 2 port-forward.

#### Step 1 — install ArgoCD (one time)

```bash
CTX="$(bash platform/bootstrap.sh up)"
REPO="https://github.com/<you>/bash-mastery-devops.git"

bash days/day27/scripts/real-argo.sh install --context "$CTX"          # preview only
bash days/day27/scripts/real-argo.sh install --context "$CTX" --apply  # server-side apply
kubectl --context "$CTX" -n argocd rollout status deploy/argocd-server --timeout=600s
```

> First run pulls ~7 container images, so the rollout can take a few minutes.
> **Don't Ctrl+C it** — wait for `successfully rolled out`. If it truly stalls,
> see [Troubleshooting](#-troubleshooting).

#### Step 2 — open the UI (optional, in its OWN terminal)

`ui` runs a port-forward that **stays in the foreground on purpose** — that's why
it looks like it "hangs". Run it in a **second terminal** and leave it open;
press Ctrl+C only when you're done looking. It is **not** part of the deploy
sequence, and you do **not** Ctrl+C it to continue — just open another terminal
for Step 3.

```bash
# terminal A — leave this running while you browse:
bash days/day27/scripts/real-argo.sh ui --context "$CTX"
#   → open https://localhost:8080   user: admin

# terminal B — get the password anytime:
bash days/day27/scripts/real-argo.sh admin-password --context "$CTX"
#   optional CLI login: argocd login localhost:8080 --username admin --password <pw> --insecure
```

> Prefer not to tie up a terminal? Skip the UI entirely — every deploy step below
> works from the CLI.

#### Step 3 — deploy your apps (pick ONE path)

Paths A and B create the **same** `frontend`/`api` apps — they're just two ways
to do it. For learning, do **A** first (one app, easy to follow), then **B**
(the real app-of-apps, the point of Day 27).

**Path A — one app at a time (simplest):**

```bash
bash days/day27/scripts/real-argo.sh render --app days/day27/examples/apps/frontend.app --repo-url "$REPO"          # just prints the YAML
bash days/day27/scripts/real-argo.sh apply  --app days/day27/examples/apps/frontend.app --context "$CTX" --repo-url "$REPO" --apply
bash days/day27/scripts/real-argo.sh sync   --app days/day27/examples/apps/frontend.app --context "$CTX"
bash days/day27/scripts/real-argo.sh status --app days/day27/examples/apps/frontend.app --context "$CTX"
#   → Application/frontend  sync=Synced  health=Healthy
```

> **Saw `not found` right after `apply`?** That's normal: ArgoCD needs a few
> seconds to reconcile a brand-new Application before it reports a status. Re-run
> `status` in a moment. (The script now says *"not reconciled yet"* in that
> window instead of the confusing *"not found"*.)

**Path B — app-of-apps (the real point of Day 27):** one root Application that
creates every child for you.

```bash
# 1) generate real child Application YAMLs for YOUR repo, then commit + push:
bash days/day27/scripts/real-argo.sh render-children --repo-url "$REPO"
git add days/day27/examples/argo-apps && git commit -m "chore: argo-apps for my repo" && git push

# 2) apply the ROOT — ArgoCD reads argo-apps/ and creates frontend + api itself:
bash days/day27/scripts/real-argo.sh apply  --app days/day27/examples/root-real.app --context "$CTX" --repo-url "$REPO" --apply
bash days/day27/scripts/real-argo.sh status --app days/day27/examples/root-real.app --context "$CTX"
```

> `root.app` (offline) fans out over `.app` files; `root-real.app` (real) points
> at `argo-apps/`, and ArgoCD creates each child from that one root — the true
> app-of-apps. If you already ran Path A for `frontend`, the root just adopts and
> keeps managing it (no harm); to start clean, run [Clean up](#-clean-up) first.

---

### 🔁 See your change flow into the cluster (the GitOps loop)

This is the whole point — **where do you edit to make ArgoCD change the
cluster?** Edit the real manifests in git, push, and ArgoCD reconciles:

1. **Where the apps live:**
   - App definitions (what ArgoCD watches): `days/day27/examples/argo-apps/*.yaml`
     (real Applications) and, offline, `days/day27/examples/apps/*.app`.
   - The actual workloads (what runs in the cluster):
     `days/day27/examples/desired/frontend/` and `.../desired/api/`
     (Deployment + Service YAML).
2. **What to change:** open `days/day27/examples/desired/frontend/deployment.yaml`
   and bump `replicas: 3` → `5` (or change the image tag).
3. **Push it:**
   ```bash
   git add days/day27/examples/desired/frontend/deployment.yaml
   git commit -m "demo: scale frontend to 5"
   git push
   ```
4. **Watch ArgoCD apply it.** The rendered apps set
   `syncPolicy.automated.selfHeal: true`, so ArgoCD polls git (~3 min) and
   reconciles on its own. To see it now:
   ```bash
   bash days/day27/scripts/real-argo.sh sync   --app days/day27/examples/apps/frontend.app --context "$CTX"
   watch kubectl --context "$CTX" -n frontend get pods
   # pods go 3 → 5, or the UI tile flips OutOfSync → Synced
   ```

That round trip — **edit git → push → ArgoCD syncs the cluster** — is exactly
what you're proving in Day 27.

> Protected contexts (e.g. `prod`) refuse `install`/`apply` without `--confirm`,
> exactly like Days 25–26. `render`/`render-children` need no tools at all.
>
> **Why `--server-side`?** ArgoCD's CRDs (e.g. `applicationsets.argoproj.io`)
> are larger than the 256KB `last-applied-configuration` annotation a plain
> client-side `kubectl apply` writes, so a normal apply fails with
> *"metadata.annotations: Too long: may not be more than 262144 bytes"*.
> `install` uses `kubectl apply --server-side --force-conflicts`, which is the
> official fix and is safe to re-run.

**Exit codes:** `0` ok · `1` apply/guard failure · `2` usage · `3` missing tool
or unreachable cluster (never fakes a change).

### 🩺 Troubleshooting

**Rollout hangs / pods stuck `Pending`.** On a small machine kind pulls ~7
ArgoCD images at once — give it a few minutes first. If it truly stalls, find out
*why* instead of Ctrl+C-ing:

```bash
kubectl --context "$CTX" -n argocd get pods
kubectl --context "$CTX" -n argocd describe pod -l app.kubernetes.io/name=argocd-server | sed -n '/Events/,$p'
kubectl --context "$CTX" describe node bash-mastery-control-plane | sed -n '/Conditions/,/Allocated/p'
```

- `FailedScheduling … Insufficient cpu/memory`, or node `DiskPressure=True` →
  free Docker disk (`docker system prune -af`) and/or raise Docker's memory,
  then re-run `install --apply`.
- `Pulling image` / slow → just wait: add `--timeout=600s` to `rollout status`.

**`admin-password` says "secret not found", or `ui` says "pod is not running".**
You ran them before ArgoCD finished starting — wait for the rollout to print
`successfully rolled out`, then retry.

**`status` says "not reconciled yet".** Normal right after `apply`; ArgoCD hasn't
processed the new Application. Re-run in a few seconds or watch the UI tile.

### 🧹 Clean up

Start fresh anytime (safe to re-run) before running the README commands again:

```bash
# delete the apps ArgoCD created
kubectl --context "$CTX" -n argocd delete application frontend api platform-root --ignore-not-found
# delete their workload namespaces
kubectl --context "$CTX" delete namespace frontend api --ignore-not-found --wait=false
# (optional) remove ArgoCD entirely
kubectl --context "$CTX" delete namespace argocd --ignore-not-found --wait=false
# (optional) tear the whole cluster down
bash platform/bootstrap.sh down
```

---

## ✅ Verify

```bash
bats days/day27/tests    # offline sync + real ArgoCD (stubbed kubectl)
```

> The real suite injects a **stub `kubectl`** via `$KUBECTL` and forces the
> `argocd` CLI absent, so it exercises render/install/apply/sync/status plus the
> kubectl fallbacks — no cluster or ArgoCD required.

---

## Recap

| Concept | One-liner |
|---|---|
| Application | maps a git source to a live dest |
| App-of-apps | one root declares many children |
| Sync status | Synced / OutOfSync, honestly re-diffed |
| Dry-run gate | non-zero on drift, for CI |
| Prune | remove undeclared live files |

Next up: **Day 28 — Chaos Engineering.**
