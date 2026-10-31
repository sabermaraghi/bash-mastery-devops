output "context" {
  description = "kubectl context for the provisioned cluster."
  value       = "kind-${var.cluster_name}"
}

output "next_steps" {
  description = "How to deploy the services once infra is up."
  value       = "cd ../.. && bash projects/devops-platform/capstone.sh deploy --context kind-${var.cluster_name}"
}
