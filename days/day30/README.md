# Day 30 — Cost & FinOps

The final skill: making the cluster *cheap*. You reserve resources (requests),
but you're billed for what you reserve — not what you use. That gap is waste, and
FinOps is the practice of finding it, pricing it, and closing it.

Today you build a cost report and a right-sizing gate over the same workload
model you've used all along.

---

## 📁 Scripts for today

| Script | Path | What it does |
|---|---|---|
| **Cost lib** | `days/day30/scripts/cost-lib.sh` | Spec parsing + cost math |
| **Cost report** | `days/day30/scripts/cost-report.sh` | Monthly spend, per workload + total |
| **Right-size** | `days/day30/scripts/rightsize.sh` | Waste/risk detection + recommendations |
| **Real cost** | `days/day30/scripts/real-cost.sh` | Option 2: the same cost + right-sizing against a live cluster (see below) |

---

## The workload model

```ini
name        = frontend
replicas    = 5
cpu_request = 500    # millicores reserved (billed)
mem_request = 512    # MiB reserved (billed)
cpu_usage   = 100    # millicores actually used
mem_usage   = 200    # MiB actually used
```

Price model: **$0.031 / core-hour** CPU, **$0.004 / GiB-hour** memory, **730 h**
per month (all overridable).

## 1. What does it cost?

```bash
bash days/day30/scripts/cost-report.sh --dir days/day30/examples
```

```
WORKLOAD         REPLICAS   CPU(m)  MEM(Mi)   COST/MO($)
---------------- -------- ------ ------- ------------
api                     3      250      256        19.16
cache                   2      200      512        11.97
frontend                5      500      512        63.88
---------------- -------- ------ ------- ------------
TOTAL                                                95.01
```

## 2. Where's the waste?

```bash
bash days/day30/scripts/rightsize.sh --dir days/day30/examples
```

```
WORKLOAD       STATUS      CPU%      MEM%    REC_CPU    REC_MEM   SAVE/MO$
-------------- ------ -------- -------- --------- --------- ---------
api            RISK        92%      70%        384        300      -9.47
cache          OK          60%      59%        200        512       0.00
frontend       WASTE       20%      39%        167        334      40.22
-------------- ------ -------- -------- --------- --------- ---------
Potential monthly savings: $30.75
RESULT: workloads need right-sizing   # exit 1
```

- **WASTE** — utilization below `--low` (30%). `frontend` reserves 5× what it
  needs; cut requests and save ~$40/mo.
- **RISK** — utilization above `--high` (90%). `api` is one spike from throttling;
  the recommendation *raises* its request (negative saving = money well spent).
- **OK** — sits in the healthy band, leaving `--target` (60%) headroom.

Recommendations size each request so usage lands at the target headroom:
`recommended = ceil(usage / (target/100))`.

## 3. As a CI gate

`rightsize.sh` exits non-zero when any workload needs attention, so it drops
straight into a pipeline:

```bash
bash days/day30/scripts/rightsize.sh --dir k8s/ --low 25 --high 85 || {
  echo "::warning::workloads need right-sizing"; exit 1;
}
```

---

## 🚀 Option 2 — real cost & FinOps on a live cluster (`real-cost.sh`)

The offline scripts price `*.workload` files — that's the **default** and what CI
tests. On a real cluster the exact same two numbers come straight from
Kubernetes, so `real-cost.sh` reuses the offline cost math (`cost-lib.sh`) and
reads:

- **what you reserve (and pay for)** = each Deployment's resource *requests*
  (`kubectl get deploy ... .spec...containers[0].resources.requests`)
- **what you actually use** = live metrics (`kubectl top pods`, via
  metrics-server)

The gap between them is the waste FinOps hunts. Both subcommands are
**read-only** — they never mutate the cluster. Set your context first:

```bash
CTX=kind-bash-mastery
```

**What does the namespace cost?**

```bash
bash days/day30/scripts/real-cost.sh report --context "$CTX" --namespace frontend
```

```
WORKLOAD         REPLICAS   CPU(m)  MEM(Mi)   COST/MO($)
---------------- --------   ------  ------- ------------
frontend                3      500      512        38.33
---------------- --------   ------  ------- ------------
TOTAL                                              38.33
```

**Where's the waste? (requests vs live usage — a FinOps CI gate)**

```bash
bash days/day30/scripts/real-cost.sh rightsize --context "$CTX" --namespace frontend \
  --low 30 --high 90 --target 60
```

```
WORKLOAD       STATUS      CPU%      MEM%    REC_CPU    REC_MEM   SAVE/MO$
-------------- ------  --------  --------  ---------  ---------  ---------
frontend       WASTE        20%       39%        167        334      24.13
-------------- ------  --------  --------  ---------  ---------  ---------
Potential monthly savings: $24.13
RESULT: workloads need right-sizing   # exit 1
```

> **Notes & safety rails:** `rightsize` needs **metrics-server** installed —
> without it (`kubectl top` fails) the command degrades gracefully with
> **exit 3** rather than guessing. Usage is matched per Deployment by
> `--selector` (default `app=<deployment>`). Prices/thresholds
> (`--cpu-price`/`--mem-price`/`--hours`/`--low`/`--high`/`--target`) mirror the
> offline flags. Both commands degrade to exit 3 when kubectl or the cluster is
> missing.

### Installing metrics-server on kind (for `rightsize`)

A fresh kind cluster has no metrics-server, so `kubectl top` (and therefore
`rightsize`) won't work until you add one. Note that `--kubelet-insecure-tls`
is **not** a `kubectl` flag — it's an argument to the metrics-server container,
so you apply the manifest first, then patch the Deployment to add it (kind's
kubelet serves a self-signed cert that metrics-server otherwise rejects):

```bash
CTX=kind-bash-mastery

# 1) install metrics-server
kubectl --context "$CTX" apply -f \
  https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 2) trust kind's kubelet cert (this is where --kubelet-insecure-tls belongs)
kubectl --context "$CTX" -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# 3) wait for rollout, then confirm metrics flow (give it ~30-60s for the first scrape)
kubectl --context "$CTX" -n kube-system rollout status deploy/metrics-server
kubectl --context "$CTX" top pods -A     # prints numbers once ready
```

`report` works **without** metrics-server (it only reads requests); only
`rightsize` needs it.

---

## ✅ Verify

```bash
bats days/day30/tests
```

---

## Recap

| Concept | One-liner |
|---|---|
| Requests vs usage | you pay for requests; the gap is waste |
| Cost report | price the whole cluster, monthly |
| WASTE | over-provisioned — cut it |
| RISK | under-provisioned — raise it |
| Right-size gate | fail CI until the fleet is efficient |

That's the course — from your first `#!/usr/bin/env bash` to running a
cost-optimized, self-healing platform, all in shell. 🎉
