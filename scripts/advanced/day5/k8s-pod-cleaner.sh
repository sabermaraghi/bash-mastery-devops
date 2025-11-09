#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ==================== CONFIGURATION ====================
# Directory for log file (defaults to /tmp if not writable elsewhere)
LOG_DIR="${LOG_DIR:-/tmp}"
LOG="$LOG_DIR/k8s-cleaner.log"

# Maximum number of parallel namespace cleanups (safe default: 10)
MAX_PARALLEL="${MAX_PARALLEL:-10}"

# Dry-run mode: set to "true" to only show what would be deleted
DRY_RUN="${DRY_RUN:-false}"

# List of namespaces to clean. Leave empty to scan ALL namespaces.
NAMESPACES=()

# Color codes for terminal output
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'  # No Color

# ==================== HELPER FUNCTIONS ====================
log() {
    local level="$1"; shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%b[%s] [K8S-CLEANER] [%s] %b%s%b\n" \
        "$YELLOW" "$timestamp" "$level" "$NC" "$message" "$NC" \
        | tee -a "$LOG"
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."

    command -v kubectl >/dev/null || {
        log "ERROR" "kubectl not found in PATH"
        exit 1
    }

    command -v jq >/dev/null || {
        log "ERROR" "jq not found. Install with: apt/brew install jq"
        exit 1
    }

    mkdir -p "$LOG_DIR"
    touch "$LOG" 2>/dev/null || {
        log "ERROR" "Cannot write to log file: $LOG"
        exit 1
    }

    log "INFO" "Prerequisites OK. Logging to: $LOG"
}

get_namespaces() {
    if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
        kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'
    else
        printf '%s\n' "${NAMESPACES[@]}"
    fi
}

clean_namespace() {
    local ns="$1"
    log "INFO" "Scanning namespace: $ns"

    local failed_pods
    failed_pods=$(kubectl get pods -n "$ns" \
        --field-selector=status.phase=Failed \
        -o json 2>/dev/null \
        | jq -r '.items[]?.metadata.name // empty' || true)

    if [[ -z "$failed_pods" ]]; then
        log "INFO" "No failed pods found in namespace '$ns'"
        return
    fi

    while IFS= read -r pod; do
        [[ -z "$pod" ]] && continue

        log "WARN" "Found failed pod: $ns/$pod"

        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY-RUN" "Would run: kubectl delete pod $pod -n $ns --grace-period=0 --force"
            continue
        fi

        log "ACTION" "Deleting pod: $ns/$pod (force + no grace)"
        if kubectl delete pod "$pod" -n "$ns" --grace-period=0 --force --wait=false >/dev/null 2>&1; then
            log "SUCCESS" "Successfully deleted pod: $ns/$pod"
        else
            log "ERROR" "Failed to delete pod: $ns/$pod"
        fi

    done <<< "$failed_pods"
}

# ==================== MAIN EXECUTION ====================
main() {
    check_prerequisites

    log "INFO" "=== Kubernetes Failed Pods Cleaner Started ==="
    log "INFO" "Mode: Dry-run=$DRY_RUN | Parallel jobs=$MAX_PARALLEL | Log=$LOG"

    # Export functions and variables for xargs parallel execution
    export -f clean_namespace log
    export LOG DRY_RUN NC YELLOW

    # Process each namespace in parallel
    get_namespaces | xargs -n 1 -P "$MAX_PARALLEL" bash -c 'clean_namespace "$0"'

    log "SUCCESS" "=== Cleaning completed successfully ==="
    log "INFO" "All done. Check log at: $LOG"
}

# ==================== RUN ====================
main "$@"
