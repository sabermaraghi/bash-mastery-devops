# Day 8: 5 Production-Ready Microservices with FastAPI + Bash + Zero-Trust Security

> **Goal**: Build **5 fully functional microservices** that can be deployed in **Kubernetes, AWS, GCP, or on-prem** with **zero-trust security**, **immutable containers**, and **full audit trail**.

## Architecture

Client → FastAPI (Python) → Bash Orchestrator → System (AWS, Docker, Files)
↑
└── Docker/Buildah/Podman (Rootless, Signed, SBOM)


## Tech Stack
| Layer | Tool |
|------|------|
| API | FastAPI + Uvicorn |
| Logic | Bash (set -euo pipefail) |
| Container | Buildah (rootless) + Podman |
| Security | Cosign, Syft, Trivy, SARIF |
| CI/CD | GitHub Actions |

## 5 Microservices

| # | Service | Endpoint | Use Case |
|---|--------|----------|---------|
| 1 | `backup-api` | `POST /backup` | Encrypted backup |
| 2 | `deploy-api` | `POST /deploy` | Zero-downtime blue-green |
| 3 | `health-api` | `GET /health` | K8s probes |
| 4 | `secret-api` | `POST /rotate` | Rotate AWS secrets |
| 5 | `cost-api` | `GET /cost` | AWS cost report |

**All services:**
- Multi-stage Dockerfile
- Buildah build script
- SBOM (CycloneDX)
- Cosign keyless signing
- Trivy scan (fail on HIGH+)
- GitHub Actions CI
- 100% testable

## Local Testing & Execution (100% Reproducible)

> **Prerequisites**:
> - `buildah` and `podman` installed (rootless)
> - AWS CLI configured (for `secret-api` and `cost-api`)
> - GPG keypair (for `backup-api` with `gpg`)

### Step 1: Build All 5 Microservices


# Build every service using the shared build script
for svc in backup deploy health secret cost; do
  cd microservice/$svc
  ../common/build.sh $svc
  cd -
done

# Output:
# Built: localhost/backup-api:latest
# Built: localhost/deploy-api:latest

## Step 2: Run All Services (Detached Mode)

# Run each service on a unique port
podman run -d -p 8001:8000 --name backup-api  localhost/backup-api:latest
podman run -d -p 8002:8000 --name deploy-api  localhost/deploy-api:latest
podman run -d -p 8003:8000 --name health-api  localhost/health-api:latest
podman run -d -p 8004:8000 --name secret-api  localhost/secret-api:latest
podman run -d -p 8005:8000 --name cost-api    localhost/cost-api:latest

# Verify all are running
podman ps

## Step 3: Test Each Endpoint

# 1. backup-api → POST /backup

curl -X POST http://localhost:8001/backup \
  -H "Content-Type: application/json" \
  -d '{
    "source": "/app",
    "encryption": "none",
    "retention_days": 1
  }'

# Expected Output:

{"status":"success","file":"/backups/data-20251111-014200.tar.gz"}

# 2. deploy-api → POST /deploy

curl -X POST http://localhost:8002/deploy \
  -H "Content-Type: application/json" \
  -d '{"version": "v2.1.0", "canary": true}'

# Expected Output:

{"deployed":"v2.1.0","mode":"canary"}

# 3. health-api → GET /health & /ready

curl http://localhost:8003/health
# → {"status":"ok"}

touch /tmp/ready
curl http://localhost:8003/ready
# → {"status":"ready"}


# 4. secret-api → POST /rotate

curl -X POST http://localhost:8004/rotate \
  -H "Content-Type: application/json" \
  -d '{"name": "db-password"}'

# Expected Output:

{"new_secret":"db-password-new-abc123"}

# 5. cost-api → GET /cost

curl http://localhost:8005/cost?days=3

# Expected Output (example):

{
  "total": 42.18,
  "services": [
    {"service": "AmazonEC2", "cost": 28.50},
    {"service": "AmazonS3", "cost": 13.68}
  ]
}

# Step 4: Cleanup (Optional)

# Stop and remove all containers
podman stop backup-api deploy-api health-api secret-api cost-api
podman rm backup-api deploy-api health-api secret-api cost-api

# Remove images (if needed)
podman rmi localhost/backup-api:latest localhost/deploy-api:latest # ...

charts/
├── microservices/           ← Umbrella Chart 
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-prod.yaml
│   ├── values-staging.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── ingress.yaml
│       ├── networkpolicy.yaml
│       └── ...
├── backup-api/              ← Subchart 1
├── deploy-api/              ← Subchart 2
├── health-api/              ← Subchart 3
├── secret-api/              ← Subchart 4
├── cost-api/                ← Subchart 5
└── monitoring/              ← Subchart 6 (Prometheus + Grafana)


## Installation and use

helm create microservices

# → 5 deployment, 5 service, ingress, secrets, configmaps

argocd/
├── applications/                 # App of Apps
│   ├── prod.yaml
│   ├── staging.yaml
│   └── dev.yaml
├── base/                         # Base configs (مشترک)
│   ├── kustomization.yaml
│   └── namespace.yaml
├── overlays/                     # محیط‌های مختلف
│   ├── prod/
│   │   ├── kustomization.yaml
│   │   └── values-prod.yaml
│   ├── staging/
│   └── dev/
└── bootstrap/                    # Bootstrap ArgoCD
    └── install.yaml


# 1. Helm Test
helm template charts/microservices --values charts/microservices/values-prod.yaml > manifest.yaml

# 2. Install using Helm

helm upgrade --install microservices-prod charts/microservices \
  --values charts/microservices/values-prod.yaml \
  --namespace microservices-prod --create-namespace

# 3. ArgoCD sync
argocd app sync microservices-prod



# 1. Installing Argo CD
kubectl create namespace argocd
kubectl apply -n argocd -f argocd/bootstrap/install.yaml

# 2. Waiting to readiness

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# 3. Registering Applications

kubectl apply -f argocd/applications/prod.yaml
kubectl apply -f argocd/applications/staging.yaml

# 4. ckecking status

argocd app list
argocd app get microservices-prod


## Velero Backup

backup/
└── velero/
    ├── install.yaml
    ├── schedule-nightly.yaml
    ├── backup-prod.yaml
    └── restore-prod.yaml

# Set Up

kubectl apply -f backup/velero/install.yaml

# Backup check

velero backup get
velero schedule get

# Recoveri Test

velero restore create --from-backup nightly-backup-20251111


## Policies 

conftest test policies/conftest/test/policy_test.rego -p policies/gatekeeper/

# Install Gatekeeper (OPA admission controller)
kubectl apply -f policies/gatekeeper/install.yaml

# Apply all security and compliance policies
kubectl apply -f policies/gatekeeper/constraints/

# Test: This pod will be REJECTED (runs as root = forbidden)
kubectl run test-pod --image=nginx --restart=Never --overrides='
{
  "apiVersion": "v1",
  "spec": {
    "containers": [
      {
        "name": "nginx",
        "image": "nginx",
        "securityContext": {
          "runAsUser": 0
        }
      }
    ]
  }
}'
# Expected output: Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request



