# Day 28 — Chaos Engineering

Chaos engineering is *disciplined* failure injection: you form a hypothesis
("the system stays healthy if a pod dies"), break something on purpose, and
verify the system recovers. Done right it's safe — which means guardrails come
**first**, blast radius **always**, and every experiment is reproducible.

Today you break the Day 26 "cluster" (pods are files) on purpose — giving
Day 29's self-healing something real to recover from.

---

## 📁 Scripts for today

| Script | Path | What it does |
|---|---|---|
| **Chaos lib** | `days/day28/scripts/chaos-lib.sh` | Steady-state, blast cap, seeded victim pick |
| **Kill** | `days/day28/scripts/chaos-kill.sh` | Inject a fault: delete some pods, safely |
| **Experiment** | `days/day28/scripts/chaos-run.sh` | hypothesis → inject → heal → verify |
| **Real chaos** | `days/day28/scripts/real-chaos.sh` | Option 2: the same experiment against a live cluster (see below) |

---

## The three rules (encoded, not documented)

| Rule | How it's enforced |
|---|---|
| **Steady state first** | `--expect E`; refuses to inject unless observed == E |
| **Blast radius** | `--max-percent` (default 50); never kills more than the cap |
| **Reproducible** | `--seed S`; the same seed picks the same victims |

## 1. Inject a fault (safely)

```bash
bash days/day28/scripts/chaos-kill.sh \
  --state-dir /tmp/cluster --name frontend --expect 5 --count 2 --seed 7
```

```
KILL frontend-3
KILL frontend-0
----------------------------
injected: killed 2/5 pods (blast cap 2, seed 7)
```

Ask for too much and the guard stops you — no accidental outage:

```
ERROR: blast radius exceeded: 4 > cap 2 (50% of 5) — raise --max-percent to override
```

And it won't touch a system that isn't already healthy:

```
ERROR: not in steady state: observed=3 expected=5 — refusing to inject
```

## 2. Run a full experiment

Inject, then let the system heal, then verify it came back:

```bash
bash days/day28/scripts/chaos-run.sh \
  --state-dir /tmp/cluster --name frontend --expect 5 --count 2 --seed 7 \
  --heal-cmd "bash days/day26/scripts/reconcile-cr.sh --cr frontend.cr --state-dir /tmp/cluster"
```

```
[1/4] steady state: observed=5 expected=5
[2/4] injecting fault (count=2 seed=7)
[3/4] healing: bash days/day26/scripts/reconcile-cr.sh ...
[4/4] verify: observed=5 expected=5
----------------------------
EXPERIMENT PASSED: system recovered to steady state
```

With **no** `--heal-cmd`, the system can't recover on its own — the experiment
**fails**, which is exactly the signal that motivates Day 29.

## 3. Preview with `--dry-run`

```bash
bash days/day28/scripts/chaos-kill.sh --state-dir /tmp/cluster --name frontend \
  --expect 5 --count 2 --seed 7 --dry-run   # lists victims, kills nothing
```

---

## 🚀 Option 2 — real chaos on a live cluster (`real-chaos.sh`)

Everything above runs offline (pods are files) — that's the **default** and
what CI tests. When you have a real kind cluster with workloads (e.g. the
Day 27 `frontend`/`api` apps), `real-chaos.sh` injects the **same disciplined
fault into real Kubernetes** by deleting real pods. The Deployment's
ReplicaSet then recreates them — the self-healing Day 29 builds on.

The three rules are enforced against real pods, and **deleting is opt-in**:
without `--apply` it only previews the victims (safe by default on a real
cluster). Set your context first (it's not shared between terminals):

```bash
CTX=kind-bash-mastery
```

**Preview** — see who would die, touch nothing:

```bash
bash days/day28/scripts/real-chaos.sh kill \
  --context "$CTX" --namespace frontend --selector app=frontend \
  --expect 3 --count 1 --seed 7
```

**Inject** — actually delete (add `--apply`):

```bash
bash days/day28/scripts/real-chaos.sh kill \
  --context "$CTX" --namespace frontend --selector app=frontend \
  --expect 3 --count 1 --seed 7 --apply
```

Watch the ReplicaSet bring it back:

```bash
kubectl --context "$CTX" -n frontend get pods -l app=frontend -w
```

**Full experiment** — steady state → inject → wait for natural recovery → verify:

```bash
bash days/day28/scripts/real-chaos.sh run \
  --context "$CTX" --namespace frontend --selector app=frontend \
  --expect 3 --count 1 --seed 7 --wait 60 --apply
```

```
[1/4] steady state: observed=3 expected=3
[2/4] injecting fault (count=1 seed=7)
KILL frontend-<hash>
[3/4] waiting up to 60s for the cluster to self-heal
[4/4] verify: observed=3 expected=3
----------------------------
EXPERIMENT PASSED: system recovered to steady state
```

> **Safety rails (same as offline):** refuses to inject unless `observed ==
> --expect`; never exceeds `--max-percent` (default 50%); `--seed` makes victim
> selection reproducible; protected contexts (`$PROTECTED_CONTEXTS`, default
> `prod,production`) require `--confirm`. Degrades gracefully (**exit 3**) when
> kubectl or the cluster is missing.

> `--expect` must match the **real** replica count. For the Day 27 apps that's
> the `replicas:` in `days/day27/examples/desired/<app>/deployment.yaml`
> (`frontend` = 3, `api` = 2). Check live with
> `kubectl --context "$CTX" -n frontend get pods -l app=frontend`.

---

## ✅ Verify

```bash
bats days/day28/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Steady state | prove health before you break things |
| Blast radius | cap the damage, always |
| Reproducible | seed the randomness |
| Experiment | inject, heal, verify recovery |
| Honest result | fails loudly if it can't self-heal |

Next up: **Day 29 — Self-Healing Systems.**
