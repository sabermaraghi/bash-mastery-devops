# infra/main.tf — declarative provisioning for the capstone platform.
#
# Two ways to stand up the cluster:
#   1. Imperative (default in the course): platform/bootstrap.sh up --metrics
#   2. Declarative (this file): `terraform apply` creates the SAME kind cluster
#      plus installs ArgoCD, so the whole platform is reproducible from code.
#
# Terraform is optional — capstone.sh up uses bootstrap.sh so the project works
# with nothing but kind + kubectl. Reach for Terraform when you want the infra
# itself under version control and `plan`/`apply`/`destroy` lifecycle.
#
#   cd projects/devops-platform/infra
#   terraform init
#   terraform apply -var="cluster_name=bash-mastery"
#   # context is then kind-bash-mastery
#   terraform destroy

terraform {
  required_version = ">= 1.5"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.7"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "kind" {}

locals {
  repo_root   = abspath("${path.module}/../../..")
  argo_script = "${local.repo_root}/days/day27/scripts/real-argo.sh"
  context     = "kind-${var.cluster_name}"
}

# 1) The Kubernetes cluster (kind = real, conformant Kubernetes in Docker).
resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true
}

# 2) Install ArgoCD into the freshly created cluster (GitOps control plane).
#
# This delegates to the Day 27 script instead of running kubectl inline, for one
# concrete reason. ArgoCD's own CRDs are enormous (applicationsets.argoproj.io is
# ~300KB), and a CLIENT-SIDE `kubectl apply` records the whole object in the
# kubectl.kubernetes.io/last-applied-configuration annotation, which Kubernetes
# caps at 262144 bytes. So a plain `kubectl apply -n argocd -f install.yaml`
# always dies with:
#
#   The CustomResourceDefinition "applicationsets.argoproj.io" is invalid:
#   metadata.annotations: Too long: may not be more than 262144 bytes
#
# real-argo.sh applies with `--server-side --force-conflicts`, which writes no
# such annotation and stays re-runnable. Reusing it keeps ONE install path, so
# the Terraform route and the `capstone.sh up` route cannot drift apart again —
# same rule as capstone.sh: orchestrate the day scripts, never re-implement them.
resource "null_resource" "argocd" {
  depends_on = [kind_cluster.this]

  triggers = {
    cluster = kind_cluster.this.name
  }

  provisioner "local-exec" {
    command = "bash '${local.argo_script}' install --context '${local.context}' --namespace '${var.argocd_namespace}' --apply --confirm"

    environment = {
      ARGOCD_MANIFEST = var.argocd_manifest
    }
  }

  # Applying manifests only *schedules* the control plane. ArgoCD cannot resolve
  # a repo revision until argocd-repo-server answers on :8081, so without this
  # wait `terraform apply` exits "successfully" and the very next command fails
  # with a ComparisonError / 'connection refused'. Wait here instead.
  provisioner "local-exec" {
    command = <<-EOT
      kubectl --context '${local.context}' -n '${var.argocd_namespace}' rollout status deploy/argocd-repo-server --timeout='${var.argocd_timeout}'
      kubectl --context '${local.context}' -n '${var.argocd_namespace}' rollout status deploy/argocd-server      --timeout='${var.argocd_timeout}'
    EOT
  }
}

# 3) Install metrics-server (needed by the Day 30 FinOps right-sizing report).
resource "null_resource" "metrics_server" {
  depends_on = [kind_cluster.this]

  triggers = {
    cluster = kind_cluster.this.name
  }

  provisioner "local-exec" {
    command = "kubectl --context kind-${var.cluster_name} apply -f ${var.metrics_manifest} && kubectl --context kind-${var.cluster_name} -n kube-system patch deployment metrics-server --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'"
  }
}
