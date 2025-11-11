#!/usr/bin/env bash
set -euo pipefail

IMAGE="localhost/backup-api:v1.0.0"
REGISTRY="ghcr.io/yourusername/backup-api"
TAG="$REGISTRY:v1.0.0"

echo "Building $TAG with Buildah..."

CONTAINER=$(buildah from python:3.12-slim)

buildah copy "$CONTAINER" api/main.py /app/main.py
buildah copy "$CONTAINER" api/requirements.txt /app/
buildah copy "$CONTAINER" scripts/backup-orchestrator.sh /app/scripts/

buildah run "$CONTAINER" -- pip install --no-cache-dir -r /app/requirements.txt
buildah run "$CONTAINER" -- chmod +x /app/scripts/backup-orchestrator.sh

buildah config --user appuser "$CONTAINER"
buildah config --label org.opencontainers.image.source=https://github.com/yourusername/bash-mastery-devops "$CONTAINER"
buildah config --cmd '["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]' "$CONTAINER"
buildah config --healthcheck 'CMD curl -f http://localhost:8000/health || exit 1' "$CONTAINER"

buildah commit "$CONTAINER" "$IMAGE"
buildah tag "$IMAGE" "$TAG"

echo "Built and tagged: $TAG"
