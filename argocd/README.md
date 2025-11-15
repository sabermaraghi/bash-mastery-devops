# ArgoCD GitOps for Microservices Platform

## Installation

kubectl apply -f bootstrap/install.yaml

## Registering Applications

kubectl apply -f applications/prod.yaml
kubectl apply -f applications/staging.yaml

## Checking The Status

argocd app list
argocd app get microservices-prod

## Manual Sync

argocd app sync microservices-prod

# Rollback

argocd app rollback microservices-prod 1

## Secrets

sops -d secrets/vault-token.sops.yaml | kubectl apply -f -


clone the repo

cd ~/devops-bash/bash-mastery-devops

mkdir -p argocd/{applications,base/overlays/{prod,staging,dev},bootstrap,projects,secrets}

# 1. Install ArgoCD
kubectl create ns argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Apply App of Apps
kubectl apply -f argocd/applications/

# 3. Access APIs
curl http://backup-api.local/health
