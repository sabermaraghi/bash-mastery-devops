#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
LOG="/var/log/k8s-cleaner.log"
NAMESPACES=("default" "kube-system" "monitoring")
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [K8S] $*" | tee -a "$LOG"; }
clean_namespace() {
  local ns="$1"
  local pods=$(kubectl get pods -n "$ns" --field-selector=status.phase=Failed -o json | jq -r '.items[].metadata.name')
  [[ -z "$pods" ]] && return
  for pod in $pods; do
    log "INFO" "Delete the corrupted Pod: $ns/$pod"
    kubectl delete pod "$pod" -n "$ns" --grace-period=0 --force &
  done
}
log "INFO" "Start cleaning broken Pods."
for ns in "${NAMESPACES[@]}"; do
  clean_namespace "$ns"
done
wait
log "SUCCESS" "Cleaning is finished."

