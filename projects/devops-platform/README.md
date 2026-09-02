# devops-platform — capstone project

The graduation project. It ties the 30 days together into one end-to-end system:
a real, GitOps-managed, self-healing, cost-observable platform on Kubernetes —
built and operated entirely with the scripts you wrote along the way.

> **Everything here is real (Option 2).** It reuses the shared foundation
> (`platform/bootstrap.sh`) and the day scripts (ArgoCD from Day 27, FinOps from
> Day 30) rather than duplicating them. The offline daily lessons stay under
> `days/`; this is where they add up to something you can actually run.

---

## Architecture

```
              ┌──────────────────────────────────────────────┐
              │            kind cluster (infra/)             │
              │                                              │
   git push ─▶│  ArgoCD (argocd ns) ──syncs──▶ backend  ns   │
              │        ▲                       frontend ns   │
              │        │ app-of-apps                         │
              │   gitops/root.yaml                           │
              │                                              │
              │  metrics-server ──▶ Day 30 cost/right-size   │
              └──────────────────────────────────────────────┘
```

- **`infra/`** — provision the cluster + platform add-ons. Two paths: the course
  scripts (`bootstrap.sh`) or **Terraform** (`terraform apply`). Same end state.
- **`gitops/`** — an ArgoCD **app-of-apps**: apply `root.yaml` and ArgoCD pulls
  the child Applications (`apps/backend.yaml`, `apps/frontend.yaml`) which deploy
  the services from Git. Change a manifest, commit, push → ArgoCD reconciles.
- **`services/`** — the actual apps:
  - `backend/` — a **Bash HTTP server** (`app/server.sh`) containerised on
    Alpine. Yes, the microservice itself is Bash — the course comes full circle.
  - `frontend/` — a static site served by nginx.

> **One `platform/`, reused — not duplicated.** The cluster-wide foundation
> (kind bootstrap, real-mode helpers) lives in the repo's top-level `platform/`.
> This project *stands on* it; the GitOps layer here is deliberately named
> `gitops/` (not `platform/`) to avoid any confusion.

---

## Requirements

| Tool | Needed for | Required? |
|---|---|---|
| **Docker** | runs the kind cluster | ✅ yes |
| **kind** | the Kubernetes cluster itself | ✅ yes |
| **kubectl** | talk to the cluster | ✅ yes |
| **Terraform** | *optional* declarative provisioning (see below) | ⬜ optional |

**No Helm and no Vagrant.** kind runs Kubernetes inside Docker (no virtual
machines, so Vagrant is never involved), and every app is deployed as **plain
YAML through ArgoCD** — there are no Helm charts to install. Terraform is only
an *alternative* to the default `bootstrap.sh` path; you can do the whole
capstone without it.

## Two ways to provision (pick one)

| | Path A — scripts (default) | Path B — Terraform (optional) |
|---|---|---|
| Command | `capstone.sh up` | `terraform apply` |
| Extra tools | none beyond kind/kubectl/Docker | + Terraform CLI |
| What it does | runs `bootstrap.sh` + installs ArgoCD & metrics-server | creates the **same** cluster + ArgoCD + metrics-server, declaratively |
| End state | context `kind-bash-mastery`, ready to `deploy` | **identical** — context `kind-bash-mastery`, ready to `deploy` |

Both paths leave you in exactly the same place. After **either**, you continue
with `capstone.sh deploy` and the rest of the steps below.

## Quickstart

```bash
# from the repo root
CTX=kind-bash-mastery

# 0) sanity-check the project offline (no cluster needed)
bash projects/devops-platform/capstone.sh validate

# 1) cluster + metrics-server + ArgoCD
bash projects/devops-platform/capstone.sh up --context "$CTX"

# 2) build the service images and load them into kind (REQUIRED for backend pods)
bash projects/devops-platform/capstone.sh images --context "$CTX"
#    (equivalent by hand:)
#    docker build -t devops-platform/backend:1.0.0 projects/devops-platform/services/backend
#    kind load docker-image devops-platform/backend:1.0.0 --name bash-mastery

# 3) deploy everything via GitOps (ArgoCD app-of-apps).
#    NOTE: ArgoCD syncs from the Git repo, not your local files. Commit & push
#    the capstone (gitops/ + services/) to the repo first, or the apps stay
#    "Sync: Unknown" with nothing deployed. See "ArgoCD GUI & the GitOps loop".
bash projects/devops-platform/capstone.sh deploy --context "$CTX"

# 4) watch it converge (and diagnose it when it doesn't)
bash projects/devops-platform/capstone.sh status --context "$CTX"
bash projects/devops-platform/capstone.sh doctor --context "$CTX"

# 5) operate: reconcile a WidgetSet CR (Day 26 operator)  — add --apply to act
bash projects/devops-platform/capstone.sh operate --context "$CTX" --apply

# 6) chaos: kill a backend pod, watch it recover (Day 28)  — add --apply to act
bash projects/devops-platform/capstone.sh chaos --context "$CTX" --apply

# 7) heal: reconcile drift + surface crashloops (Day 29)   — add --apply to act
bash projects/devops-platform/capstone.sh heal --context "$CTX" --apply

# 8) FinOps: what does it cost? (Day 30)
bash projects/devops-platform/capstone.sh cost --context "$CTX"

# teardown (add --all to also delete the cluster)
bash projects/devops-platform/capstone.sh down --context "$CTX" --all
```

### Prefer Terraform for step 1? (optional)

If you'd rather provision declaratively, replace **step 1** (`capstone.sh up`)
with Terraform. Everything else (steps 0, 2–8) is unchanged.

First install Terraform the **official** way (the `snap` package is community-
maintained, not by HashiCorp):

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
terraform -version   # verify
```

Then provision the cluster from code:

```bash
cd projects/devops-platform/infra
terraform init                                   # download providers (first run only)
terraform apply -var="cluster_name=bash-mastery" # type 'yes' to confirm
cd ../../..                                       # back to repo root
```

**What `terraform apply` actually does** (so it's not a black box): it creates
the kind cluster `bash-mastery`, then installs ArgoCD and a kind-patched
metrics-server into it — the same end state as `capstone.sh up`. When it
finishes it prints two outputs: `context` (`kind-bash-mastery`) and
`next_steps` (the exact `deploy` command to run next).

Now just resume at **step 2** above with `CTX=kind-bash-mastery`. To tear the
Terraform-provisioned cluster down again, use Terraform (not `capstone.sh down
--all`) so its state stays consistent:

```bash
cd projects/devops-platform/infra
terraform destroy -var="cluster_name=bash-mastery"
```

> Rule of thumb: if you created the cluster with `capstone.sh up`, tear it down
> with `capstone.sh down --all`. If you created it with `terraform apply`, tear
> it down with `terraform destroy`. Don't mix the two on the same cluster.

### About the container images

The **backend** runs a custom image, `devops-platform/backend:1.0.0`, that only
exists on your machine after you build it. A kind cluster cannot pull it from
Docker Hub, so you must build it and load it into the kind nodes, or the backend
pods sit in `ErrImagePull` (which is exactly why the chaos step aborts with
`observed=0 expected=2` — there are no running backend pods to experiment on).

```bash
# build the backend image from its Dockerfile
docker build -t devops-platform/backend:1.0.0 projects/devops-platform/services/backend

# copy it into the kind cluster's nodes (kind can't reach your local Docker daemon)
kind load docker-image devops-platform/backend:1.0.0 --name bash-mastery

# if the Deployment already existed while pods were in ErrImagePull, nudge it:
kubectl --context kind-bash-mastery -n backend rollout restart deploy/backend
kubectl --context kind-bash-mastery -n backend rollout status  deploy/backend
```

The **frontend** uses a stock public image (`nginx:1.27-alpine`), so it comes up
without any build. Building + loading `devops-platform/frontend:1.0.0` is only
needed if you want to serve the custom `index.html`:

```bash
docker build -t devops-platform/frontend:1.0.0 projects/devops-platform/services/frontend
kind load docker-image devops-platform/frontend:1.0.0 --name bash-mastery
kubectl --context kind-bash-mastery -n frontend rollout restart deploy/frontend
```

---

## ArgoCD GUI & the GitOps loop

### Open the ArgoCD web UI

ArgoCD ships with a web UI, but it isn't exposed outside the cluster by default.
Port-forward it and log in as `admin`:

```bash
# forward the UI to https://localhost:8080 (leave this running in its own terminal)
kubectl --context kind-bash-mastery -n argocd port-forward svc/argocd-server 8080:443

# in another terminal, grab the auto-generated admin password
kubectl --context kind-bash-mastery -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Open <https://localhost:8080> (accept the self-signed cert), user `admin`, and
the password from above. You'll see `platform-root` and its children `backend`
and `frontend`, each with a live sync/health status and a resource tree.

Prefer the CLI? The `argocd` binary does the same:

```bash
argocd login localhost:8080 --username admin --password '<password>' --insecure
argocd app list
argocd app get platform-root
```

### Where do we "commit and sync" apps?

This is real GitOps: **ArgoCD deploys what's in the Git repo, not what's on your
laptop.** The Applications point at
`https://github.com/ericvalijani/bash-mastery-devops.git` at `HEAD`, paths under
`projects/devops-platform/`. So the workflow is:

1. **Edit** a manifest locally (e.g. bump `replicas` or the image tag).
2. **Commit & push** to the repo/branch ArgoCD watches:
   ```bash
   git add projects/devops-platform
   git commit -m "chore(capstone): bump backend replicas"
   git push
   ```
3. **Sync** — with `automated: { prune, selfHeal }` on (as configured), ArgoCD
   pulls and applies within ~3 minutes automatically. To apply immediately,
   click **Sync** in the UI or run:
   ```bash
   argocd app sync platform-root
   ```

> If `capstone.sh status` shows `platform-root  Sync: Unknown` with nothing
> deployed, it almost always means the capstone manifests aren't on the branch
> ArgoCD is watching yet — commit & push them (step 2 above), then sync.

---

## Running on a cluster other than kind

The **app layer is portable**: the services are plain YAML deployed by ArgoCD,
which is standard Kubernetes, so they run on any conformant cluster — EKS, GKE,
AKS, k3s, minikube, etc. Only the *provisioning* is kind-specific.

To target an existing non-kind cluster, skip `up`/Terraform and point the real
commands at your context:

```bash
CTX=my-eks-context   # whatever `kubectl config get-contexts` shows

# ArgoCD + metrics-server may already exist on a managed cluster; if not:
kubectl --context "$CTX" create namespace argocd
# NOTE: --server-side is mandatory, not a preference (see troubleshooting below)
kubectl --context "$CTX" -n argocd apply --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

bash projects/devops-platform/capstone.sh deploy --context "$CTX"
bash projects/devops-platform/capstone.sh status --context "$CTX"
```

What is kind-specific (and safe to ignore elsewhere):

- `capstone.sh up` and `infra/` Terraform — they *create* a local kind cluster.
  On a managed cluster the cloud/provider already did this.
- The metrics-server `--kubelet-insecure-tls` patch — a kind quirk; most managed
  clusters ship a working metrics-server already (needed only for `cost`
  right-sizing).

**Do you need Vagrant or Helm on another cluster? No.** Kubernetes itself never
requires either:

- **Vagrant** only matters if *you* choose to run K8s inside VMs (e.g. an old
  minikube VM driver, or a manual kubeadm-on-VMs lab). Managed clusters and the
  Docker-driver minikube need none. If you go the VM route, that's a
  minikube/Vagrant setup step outside this repo — the capstone doesn't add one.
- **Helm** is an optional package manager. These manifests are plain YAML, so
  Helm is never required. (ArgoCD *can* render Helm charts, but this project
  uses none.)

---

## The 9 Phase-5/6 days are each wired to a real command

This capstone doesn't just *mention* the DevOps/platform days — every one of
Days 22–30 is invoked by a real step (the mutating ones preview by default and
act with `--apply`):

| Day | Skill | Where it runs in the capstone |
|---|---|---|
| 22 | Containers & images | `services/backend/Dockerfile` (Bash HTTP server) + `services/frontend/Dockerfile` |
| 23 | CI/CD | `.github/workflows/capstone.yml` (validate + shellcheck + BATS) |
| 24 | GitOps foundations | `gitops/` app-of-apps model |
| 25 | kubectl plumbing | every real command (via day25 `kubectl-lib.sh`) + `status` |
| 26 | Operators / reconcile | `capstone.sh operate` → day26 `real-operator.sh` + `ops/widgetset.cr` |
| 27 | ArgoCD | `capstone.sh up` (installs ArgoCD) + `deploy` (app-of-apps) → day27 `real-argo.sh` |
| 28 | Chaos engineering | `capstone.sh chaos` → day28 `real-chaos.sh` |
| 29 | Self-healing | `capstone.sh heal` → day29 `real-heal.sh` |
| 30 | Cost & FinOps | `capstone.sh cost` → day30 `real-cost.sh` |

Days 1–21 are the invisible foundation underneath (strict mode, functions,
args, error handling, BATS, pre-commit, security/zero-trust — e.g. the backend
container runs as a non-root user, a Day 18 habit).

---

## Verify

```bash
bats projects/devops-platform/tests
```

The tests run fully offline (they exercise `validate` and argument handling), so
this project stays CI-green alongside the daily lessons.

## Troubleshooting the real cluster

### `ComparisonError: ... dial tcp <ip>:8081: connect: connection refused`

Every Application shows it at once and the UI toasts *"Unable to load data"*.
Port **8081** is `argocd-repo-server`, the component that renders manifests from
Git. The message means the application-controller/API could not reach it — a
**control-plane readiness problem, not a manifest problem**. Common causes:

1. ArgoCD was applied but the pods are not `Available` yet (most common right
   after `up`/install, or after a laptop reboot restarts the kind node).
2. `argocd-repo-server` is `CrashLoopBackOff`/`OOMKilled` (memory pressure on
   the kind node).
3. ArgoCD was never actually installed (an install preview without `--apply`).

Fix / inspect:

```bash
bash projects/devops-platform/capstone.sh doctor --context "$CTX"
kubectl --context "$CTX" -n argocd rollout status deploy/argocd-repo-server
kubectl --context "$CTX" -n argocd logs deploy/argocd-repo-server --tail=50
# force a fresh comparison once repo-server is Available
kubectl --context "$CTX" -n argocd delete pod -l app.kubernetes.io/name=argocd-repo-server
```

`capstone.sh up` and `capstone.sh deploy` now wait for the ArgoCD control plane
(`argocd-repo-server`, `argocd-server`, the application-controller) to become
Available before continuing, so the error should not appear from a clean run.
Override the wait with `ARGOCD_TIMEOUT=300s` or the namespace with `ARGOCD_NS`.

### Apps are `Healthy` but `Sync: Unknown` (still `:8081 connection refused`)

This combination looks contradictory but is precise, and it is worth reading
carefully because it tells you exactly which half of ArgoCD is broken:

- **Health** is computed from live objects the application-controller already
  watches in-cluster. Your Deployments are genuinely fine, so Health stays
  `Healthy`.
- **Sync** requires rendering the manifests in Git and diffing them, and *only*
  `argocd-repo-server` can do that. With it down, ArgoCD cannot resolve the repo
  revision at all, so Sync degrades to `Unknown` — the app tiles show
  `Synced 0 / OutOfSync 0 / Unknown 3`.

So `Healthy + Unknown` means **your services are fine and the repo-server is
not**. Nothing is wrong with your manifests, your branch, or your images.

If `deploy` times out waiting on `argocd-repo-server` while every other ArgoCD
component returns instantly, the repo-server is flapping rather than missing.
Check how often it has restarted and why it last died:

```bash
bash projects/devops-platform/capstone.sh doctor --context "$CTX"
```

`doctor` now prints a `RESTARTS` / `LAST_EXIT` / `CODE` table plus node pressure.
A high restart count with `LAST_EXIT=OOMKilled` and `CODE=137` is the classic
kind-on-a-laptop failure: the repo-server is the heaviest memory consumer
(git clone + manifest render) and the upstream non-HA `install.yaml` sets **no
memory request or limit**, so it is the first thing a squeezed node kills. Give
it a floor and restart it:

```bash
# preview the patch
bash projects/devops-platform/capstone.sh argocd-repair --context "$CTX"
# apply it (requests 100m/256Mi, limits 500m/1Gi by default)
bash projects/devops-platform/capstone.sh argocd-repair --context "$CTX" --apply
bash projects/devops-platform/capstone.sh deploy        --context "$CTX"
```

Tune with `ARGOCD_REPO_MEM=2Gi` / `ARGOCD_REPO_CPU=1`. If `MEM_PRESSURE=True`
the **node itself** is out of memory and no container limit will help — raise the
Docker/Podman VM memory (4 GB+ for ArgoCD plus these services), or free room by
scaling the demo workloads down while you debug:

```bash
kubectl --context "$CTX" -n backend  scale deploy/backend  --replicas=1
kubectl --context "$CTX" -n frontend scale deploy/frontend --replicas=1
```

Note those scales are drift ArgoCD will reconcile back to the Git value of `2`;
that is the self-healing loop from Day 29 doing its job, not a new bug.

### `backend` Application is `Degraded` while `frontend` is `Healthy`

The frontend runs stock `nginx:1.27-alpine` (pullable), the backend runs the
locally built `devops-platform/backend:1.0.0` — so only the backend can fail in
two capstone-specific ways. **Check the pod status first, it tells you which:**

```bash
kubectl --context "$CTX" -n backend get pods
```

**`ErrImagePull` / `ImagePullBackOff`** — the image was never loaded into the
kind node. Build + load it:

```bash
bash projects/devops-platform/capstone.sh images --context "$CTX"
kubectl --context "$CTX" -n backend rollout restart deploy/backend
```

**`CrashLoopBackOff`** — the image is present, the container itself is dying.
The pod is `Synced` (Git is fine) but never `1/1 Ready`, so the liveness probe
kills it on a loop. Look at what the Bash server actually said:

```bash
kubectl --context "$CTX" -n backend logs deploy/backend --tail=30
kubectl --context "$CTX" -n backend logs deploy/backend --previous --tail=30
kubectl --context "$CTX" -n backend describe pod -l app=backend | sed -n '/Events:/,$p'
```

Two bugs in `services/backend/app/server.sh` caused exactly this and are now
fixed — rebuild the image to pick up the fix:

1. **`nc -q 1` is not a busybox flag.** `-q` belongs to GNU/OpenBSD netcat;
   busybox `nc` (what Alpine ships) rejects it with a usage error. The `|| true`
   at the end of the loop swallowed that error, so the script spun in a tight
   loop, never bound port 8080, and every probe got connection-refused.
2. **The request was read from the container's stdin, not from the socket.** The
   `$(...)` that parsed the request line ran *before* `nc` started listening and
   saw immediate EOF, so every path resolved to empty → `404` → `/healthz` and
   `/readyz` never returned 200 even when the port was up.

The rewritten server pipes the request back through a FIFO
(`nc` stdout → FIFO → handler → `nc` stdin), drains the whole header block
before replying, and passes only `-l -p` to `nc`. Apply it with:

```bash
bash projects/devops-platform/capstone.sh images --context "$CTX"
kubectl --context "$CTX" -n backend rollout restart deploy/backend
kubectl --context "$CTX" -n backend rollout status deploy/backend
```

Because the tag stays `1.0.0` and `imagePullPolicy: IfNotPresent`, ArgoCD sees
no manifest change — `kind load` + `rollout restart` is what swaps the code in.
Verify the service by hand:

```bash
kubectl --context "$CTX" -n backend run curl --rm -it --restart=Never \
  --image=curlimages/curl -- curl -s http://backend/healthz
```

### `metadata.annotations: Too long: may not be more than 262144 bytes`

Seen while installing ArgoCD — from `terraform apply` (`local-exec provisioner
error` on `null_resource.argocd`) or from a hand-run `kubectl apply`:

```
The CustomResourceDefinition "applicationsets.argoproj.io" is invalid:
metadata.annotations: Too long: may not be more than 262144 bytes
```

This is **not** a cluster, network, or manifest problem. A *client-side*
`kubectl apply` stores a full copy of every object it applies in the
`kubectl.kubernetes.io/last-applied-configuration` annotation, and Kubernetes
caps annotations at 262144 bytes. ArgoCD's `applicationsets.argoproj.io` CRD is
larger than that on its own, so a client-side apply of `install.yaml` can never
succeed — it fails the same way on every cluster, every time.

The fix is a **server-side apply**, which computes the diff on the API server and
writes no such annotation:

```bash
kubectl --context "$CTX" -n argocd apply --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

`--force-conflicts` makes re-runs idempotent by taking ownership of fields a
previous apply already manages.

Both install routes now go through `days/day27/scripts/real-argo.sh install`,
which does exactly that — `infra/main.tf` calls the script rather than running
its own `kubectl apply`, so the Terraform and `capstone.sh up` paths cannot drift
apart again. A BATS test fails the build if a client-side apply comes back.

**Why a failed install looks like the `:8081` error later.** When this error
aborts the provisioner, ArgoCD is left *partially* installed — CRDs and
Deployments may exist while the install is incomplete, and Terraform marks the
resource as not created, so the next `apply` retries and fails identically. An
incomplete control plane is exactly what produces
`ComparisonError ... :8081 connection refused` and `Sync: Unknown` minutes later.
Fixing the apply mode fixes both symptoms at the source.

### `operate` fails: `namespaces "widgets" not found`

```
Error from server (NotFound): error when creating "STDIN": namespaces "widgets" not found
{"level":"ERROR","component":"real-operator","message":"reconcile failed for WidgetSet/widgets"}
```

This is not an operator bug. `backend` and `frontend` land in namespaces that
ArgoCD creates for them, because their Applications carry:

```yaml
syncPolicy:
  syncOptions:
    - CreateNamespace=true
```

The Day 26 operator step is deliberately **not** GitOps-managed — that is the
whole point of the exercise — so nothing owns the `widgets` namespace.
`real-operator.sh` only runs `kubectl --namespace widgets apply -f -`, and
`kubectl apply` never creates a missing namespace.

On a long-lived cluster the namespace survived from an earlier run, so this
stayed hidden for weeks. **Rebuild the cluster and it appears immediately** —
which is exactly why it showed up right after the Terraform rebuild.

`capstone.sh operate` now creates the namespace itself (idempotently) before
delegating, so a fresh cluster works with no manual step. Preparing the
environment belongs to the orchestrator; the day script stays a pure reconciler.
A preview (`operate` without `--apply`) still refuses to touch the cluster, but
now tells you the namespace is missing instead of surfacing a raw `NotFound` —
note that even a server dry-run fails against a namespace that does not exist.

`capstone.sh down` now deletes `widgets` alongside the service namespaces, so
teardown is symmetric with what `operate` created.

### Files that must never be committed

`terraform apply` writes several files next to `main.tf`. Three kinds must stay
out of Git:

| Path | Why it must be ignored |
| --- | --- |
| `infra/terraform.tfstate`, `*.tfstate.backup` | The kind provider stores the generated kubeconfig — including `client_certificate` and `client_key` — in **plaintext**. State files are also machine-local and cause merge conflicts. |
| `infra/bash-mastery-config` | The cluster kubeconfig the kind provider writes as `<cluster_name>-config`. It holds admin credentials for the cluster. |
| `infra/.terraform/` | ~40 MB of downloaded provider binaries. Git keeps them forever, in every clone. |

`infra/.terraform.lock.hcl` is the exception: **commit that one.** It pins
provider versions so every machine resolves identical providers.

The repo `.gitignore` now covers all of these. Files already tracked keep being
tracked until they are removed from the index:

```bash
git rm -r --cached projects/devops-platform/infra/.terraform \
  projects/devops-platform/infra/terraform.tfstate \
  projects/devops-platform/infra/terraform.tfstate.backup \
  projects/devops-platform/infra/bash-mastery-config
git commit    # files stay on disk; only Git stops tracking them
```

The leaked credentials are for a local kind cluster reachable only on
`127.0.0.1`, and rebuilding the cluster invalidates them — so the practical risk
here is low. Treat it as a habit worth fixing now: the identical mistake with an
EKS or GKE state file leaks credentials to a real cluster, and state files are
the single most common source of real-world secret leaks in Terraform repos.

### Apps stay `Sync: Unknown` / `targetRevision`

The Applications track branch **`capstone`** (`targetRevision: capstone`), not
`HEAD`. ArgoCD reads Git, never your working copy, so commit and push the
capstone files to that branch before expecting a sync. If you rename or merge
the branch, update `targetRevision` in `gitops/root.yaml`, `gitops/apps/*.yaml`.
