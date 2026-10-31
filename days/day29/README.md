# Day 29 — Self-Healing Systems

Yesterday you broke the cluster on purpose and the experiment *failed* — nothing
put the dead pods back. Today you build the thing that does: a **watchdog** that
probes for liveness, restarts what died, and knows when to give up.

This is Kubernetes' core promise in shell: declare the desired state, then let a
control loop continuously drive reality back toward it.

---

## 📁 Scripts for today

| Script | Path | What it does |
|---|---|---|
| **Health lib** | `days/day29/scripts/health-lib.sh` | Liveness probe, healthy count, restart bookkeeping |
| **Heal** | `days/day29/scripts/heal.sh` | One remediation pass (restart policy + backoff) |
| **Watchdog** | `days/day29/scripts/watchdog.sh` | The control loop: heal until healthy or budget spent |
| **Real heal** | `days/day29/scripts/real-heal.sh` | Option 2: the same control loop against a live cluster (see below) |

---

## Liveness probe

A pod (a file whose content is its image) is **dead** if it's missing, empty,
marked `CRASHED`, or running a `:bad` image that crashes on start. Everything
else is alive.

## 1. Heal a single time

Kill two pods, then run one heal pass:

```bash
rm /tmp/cluster/pods/frontend-1 /tmp/cluster/pods/frontend-3
bash days/day29/scripts/heal.sh \
  --state-dir /tmp/cluster --name frontend --replicas 5 --image nginx:1.25
```

```
RESTART frontend-1 (attempt 1/5, image=nginx:1.25)
RESTART frontend-3 (attempt 1/5, image=nginx:1.25)
----------------------------
healed: 2 restart(s), 0 crashloop — healthy 5/5
```

## 2. Restart policy

| Policy | Behavior |
|---|---|
| `Always` (default) | restart any dead pod |
| `OnFailure` | restart any dead pod (same here — liveness-driven) |
| `Never` | report only, never restart |

```bash
bash days/day29/scripts/heal.sh --state-dir /tmp/cluster --name frontend \
  --replicas 5 --image nginx:1.25 --restart-policy Never
# UNHEALTHY frontend-1 (policy=Never, not restarting)
```

## 3. The watchdog loop — turning yesterday's failure into a pass

```bash
# inject with Day 28, then let the watchdog converge the system
bash days/day28/scripts/chaos-kill.sh --state-dir /tmp/cluster --name frontend --expect 5 --count 2 --seed 7
bash days/day29/scripts/watchdog.sh \
  --state-dir /tmp/cluster --name frontend --replicas 5 --image nginx:1.25 --max-iterations 5
```

```
=== watchdog pass 1/5 ===
RESTART frontend-0 (attempt 1/5, image=nginx:1.25)
RESTART frontend-3 (attempt 1/5, image=nginx:1.25)
----------------------------
healed: 2 restart(s), 0 crashloop — healthy 5/5
watchdog: system healthy after 1 pass(es)
```

## 4. CrashLoopBackOff — knowing when to stop

A restart loop that never fixes anything is worse than none. Deploy a `:bad`
image and the watchdog restarts up to `--max-restarts`, then gives up:

```bash
bash days/day29/scripts/watchdog.sh --state-dir /tmp/cluster --name broken \
  --replicas 1 --image app:bad --max-restarts 2 --max-iterations 5
```

```
CRASHLOOP broken-0 (restarts=2, giving up)
watchdog: system still degraded after 5 pass(es)   # exit 1
```

Stable pods reset their restart counter, so transient blips don't count against
a pod forever — only sustained failure reaches CrashLoopBackOff.

---

## 🚀 Option 2 — real self-healing on a live cluster (`real-heal.sh`)

The offline scripts imitate a control loop over the file-based cluster — that's
the **default** and what CI tests. On a real cluster Kubernetes already restarts
dead containers, so a real watchdog focuses on the parts K8s does **not** do for
you:

1. **Reconcile drift** — if the Deployment's replica count was changed away from
   the desired value, scale it back.
2. **Surface crashloops** — detect pods stuck in `CrashLoopBackOff` (or past a
   restart budget) that will never recover on their own.
3. **Converge** — loop until the Deployment reports all replicas ready, or the
   iteration budget runs out (degraded).

This pairs directly with Day 28: kill pods with `real-chaos.sh`, then watch
`real-heal.sh` (and Kubernetes) drive the Deployment back to steady state.
Scaling is **opt-in** — without `--apply` it only reports (safe by default).
Set your context first (it isn't shared between terminals):

```bash
CTX=kind-bash-mastery
```

**One reconcile pass (report only):**

```bash
bash days/day29/scripts/real-heal.sh heal \
  --context "$CTX" --namespace frontend --deployment frontend --replicas 3
```

**Reconcile for real (add `--apply`):**

```bash
bash days/day29/scripts/real-heal.sh heal \
  --context "$CTX" --namespace frontend --deployment frontend --replicas 3 --apply
```

**The watchdog loop — turn Day 28's chaos into a recovery:**

```bash
# 1) inject with Day 28
bash days/day28/scripts/real-chaos.sh kill \
  --context "$CTX" --namespace frontend --selector app=frontend \
  --expect 3 --count 1 --seed 7 --apply

# 2) let the watchdog converge the Deployment back to steady state
bash days/day29/scripts/real-heal.sh watch \
  --context "$CTX" --namespace frontend --deployment frontend --replicas 3 \
  --apply --max-iterations 10 --interval 5
```

```
=== watchdog pass 1/10 ===
----------------------------
reconciled: healthy 3/3 ready, 0 crashloop
watchdog: Deployment healthy after 1 pass(es)
```

> **Safety rails:** refuses protected contexts (`$PROTECTED_CONTEXTS`, default
> `prod,production`) without `--confirm`; `--max-restarts` sets the crashloop
> budget; degrades gracefully (**exit 3**) when kubectl or the cluster is
> missing. `--replicas` is the desired count — for the Day 27 apps that's the
> `replicas:` in `days/day27/examples/desired/<app>/deployment.yaml`
> (`frontend` = 3, `api` = 2). Pod crashloops are matched by `--selector`
> (default `app=<deployment>`).

---

## ✅ Verify

```bash
bats days/day29/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Liveness probe | is this pod actually alive? |
| Restart policy | Always / OnFailure / Never |
| Backoff counter | resets when a pod goes stable |
| CrashLoopBackOff | stop restarting a hopeless pod |
| Control loop | continuously reconcile toward desired state |

Next up: **Day 30 — Cost & FinOps.**
