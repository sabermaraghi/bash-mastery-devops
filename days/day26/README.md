# Day 26 — Kubernetes Operators & CRDs

An **operator** is just Day 24's reconcile loop pointed at a *custom resource*.
You declare a `spec` (desired), the controller observes reality, converges the
two, and writes back a `status`. It runs continuously and is **level-triggered**
— it always drives toward the current spec, no matter how it got out of sync.

Today you build a mini-operator for a `WidgetSet` CRD (think: a Deployment).
No real cluster needed — "pods" are files, so every reconcile is inspectable.

---

## 📁 Scripts for today

| Script | Path | What it does |
|---|---|---|
| **Operator lib** | `days/day26/scripts/operator-lib.sh` | `cr_get`, `is_uint`, `count_pods` |
| **Reconcile** | `days/day26/scripts/reconcile-cr.sh` | One reconcile pass for a single CR |
| **Control loop** | `days/day26/scripts/operator.sh` | Watch a dir of CRs; `--once` or `--interval` |
| **Real (Option 2)** | `days/day26/scripts/real-operator.sh` | Same pattern against a live cluster (see below) |

---

## 1. The custom resource

A CR is a declarative spec. Our `WidgetSet` has `replicas` and `image`:

```ini
kind = WidgetSet
name = frontend
replicas = 3
image = nginx:1.25
```

## 2. One reconcile pass

```bash
bash days/day26/scripts/reconcile-cr.sh \
  --cr days/day26/examples/frontend.cr --state-dir /tmp/cluster
```

```
CREATE frontend-0
CREATE frontend-1
CREATE frontend-2
----------------------------
reconciled: frontend (3 created, 0 updated, 0 deleted) phase=Ready
```

The controller now wrote a **status subresource** at
`/tmp/cluster/status/frontend.status`:

```ini
desiredReplicas=3
observedReplicas=3
readyReplicas=3
image=nginx:1.25
phase=Ready
```

## 3. Level-triggered convergence

Edit the spec and reconcile again — the controller does the minimum to converge:

| Change | Actions taken |
|---|---|
| `replicas: 3 → 5` | `CREATE frontend-3`, `CREATE frontend-4` |
| `replicas: 5 → 2` | `DELETE frontend-2..4` |
| `image: → nginx:1.26` | `UPDATE` every pod (rolling to new image) |
| no change | `already reconciled` (no-op) |

Because it's level-triggered, deleting a pod out-of-band and re-running simply
re-creates it — self-healing falls out for free (Day 29 builds on this).

## 4. The control loop

```bash
# single sweep over every *.cr (great for CI)
bash days/day26/scripts/operator.sh --cr-dir manifests/ --state-dir /tmp/cluster --once

# run continuously, resyncing every 10s (Ctrl-C to stop)
bash days/day26/scripts/operator.sh --cr-dir manifests/ --state-dir /tmp/cluster --interval 10
```

---

## Two ways to run

**Option 1 (default, offline)** is everything above: a mini-operator whose
"pods" are files, fully BATS-tested, no cluster, always CI-green.

**Option 2 (real)** runs the *same* reconcile pattern against a real Kubernetes
cluster. It **reuses the offline CR parser** (`operator-lib.sh`: `cr_get`,
`is_uint`) and the **Day 25 kubectl safety rails** (`kubectl-lib.sh`:
`is_protected_context`, `is_valid_namespace`), then converges the cluster toward
the `WidgetSet` by managing a **Deployment** — Kubernetes' own built-in
reconciler. That's the honest lesson: *a real operator composes existing
controllers rather than reinventing the loop.*

### 🚀 Option 2 — reconcile a CR against a live cluster

Prereqs and cluster setup are identical to Day 25 (`brew install kubectl kind`,
then `CTX="$(bash platform/bootstrap.sh up)"`). The script is
`days/day26/scripts/real-operator.sh`.

| Offline (Option 1) | Real (Option 2) |
|---|---|
| `reconcile-cr.sh` → pod files | `real-operator.sh reconcile` → a Deployment |
| `count_pods` status | `real-operator.sh status` (reads `.status.readyReplicas`) |
| `operator.sh` control loop | `real-operator.sh watch` (`--once` / `--interval`) |
| (n/a) | `real-operator.sh delete` (tears the Deployment down) |
| dry-run planning | `--dry-run=server` unless `--apply` |

```bash
CTX="$(bash platform/bootstrap.sh up)"
kubectl --context "$CTX" create namespace demo --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -
CR=days/day26/examples/frontend.cr

# preview (safe server-side dry-run — changes nothing)
bash days/day26/scripts/real-operator.sh reconcile --cr "$CR" --context "$CTX" --namespace demo

# converge for real, then watch it become Ready
bash days/day26/scripts/real-operator.sh reconcile --cr "$CR" --context "$CTX" --namespace demo --apply
bash days/day26/scripts/real-operator.sh status    --cr "$CR" --context "$CTX" --namespace demo
kubectl --context "$CTX" -n demo get deploy,pods

# level-triggered proof: hand-delete a pod, reconcile again — it self-heals
kubectl --context "$CTX" -n demo delete pod -l app.kubernetes.io/name=frontend --wait=false
bash days/day26/scripts/real-operator.sh reconcile --cr "$CR" --context "$CTX" --namespace demo --apply

# continuous loop (like a real operator); Ctrl+C to stop
bash days/day26/scripts/real-operator.sh watch --cr-dir days/day26/examples --context "$CTX" --namespace demo --interval 5 --apply

# clean up when done (--wait=false returns immediately)
bash days/day26/scripts/real-operator.sh delete --cr "$CR" --context "$CTX" --namespace demo
kubectl --context "$CTX" delete namespace demo --wait=false
```

> Protected contexts (e.g. `prod`) refuse `--apply`/`delete` without `--confirm`,
> exactly like Day 25.

**Exit codes:** `0` ok · `1` reconcile/guard failure · `2` usage · `3` missing
tool or unreachable cluster (never fakes a change).

---

## ✅ Verify

```bash
bats days/day26/tests    # offline operator + real (stubbed kubectl)
```

> The real suite injects a **stub `kubectl`** via `$KUBECTL`, so it exercises
> every guard and the full reconcile/status/watch/delete flow with no cluster.

---

## Recap

| Concept | One-liner |
|---|---|
| CRD / CR | a custom resource = a declarative spec |
| Reconcile | make observed match desired |
| Status subresource | the controller reports what it sees |
| Level-triggered | always drive toward current spec |
| Control loop | reconcile every CR, forever |

Next up: **Day 27 — ArgoCD App-of-Apps.**
