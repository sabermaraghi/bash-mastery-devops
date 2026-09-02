# infra/ — provision the platform

Two interchangeable ways to get the cluster + platform add-ons (ArgoCD,
metrics-server) up:

## Option A — scripts (default, zero extra tools)

```bash
# from repo root
bash projects/devops-platform/capstone.sh up --context kind-bash-mastery
```

This calls `platform/bootstrap.sh up --metrics` then Day 27's `real-argo.sh
install` — the same scripts you built during the course.

## Option B — Terraform (infra as code)

Requires the Terraform CLI plus kind + kubectl on PATH.

```bash
cd projects/devops-platform/infra
terraform init
terraform apply -var="cluster_name=bash-mastery"
# ... work ...
terraform destroy -var="cluster_name=bash-mastery"
```

`terraform apply` creates the kind cluster, installs ArgoCD, and installs a
kind-patched metrics-server — the exact same end state as Option A, but captured
declaratively so it lands in version control and gets a real plan/apply/destroy
lifecycle.

> Both paths converge on context `kind-bash-mastery`. After either one, deploy
> the services with `capstone.sh deploy --context kind-bash-mastery`.
