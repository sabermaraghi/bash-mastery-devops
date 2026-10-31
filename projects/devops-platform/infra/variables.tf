variable "cluster_name" {
  description = "kind cluster name; kubectl context becomes kind-<name>."
  type        = string
  default     = "bash-mastery"
}

variable "argocd_manifest" {
  description = "ArgoCD install manifest URL."
  type        = string
  default     = "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
}

variable "argocd_namespace" {
  description = "Namespace ArgoCD is installed into."
  type        = string
  default     = "argocd"
}

variable "argocd_timeout" {
  description = "How long to wait for the ArgoCD control plane to become Available."
  type        = string
  default     = "180s"
}

variable "metrics_manifest" {
  description = "metrics-server install manifest URL."
  type        = string
  default     = "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
}
