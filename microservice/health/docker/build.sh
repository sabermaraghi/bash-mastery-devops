#!/usr/bin/env bash
set -euo pipefail

IMAGE="localhost/health-api:v1.0.0"
TAG="ghcr.io/yourusername/health-api:v1.0.0"

buildah bud -f docker/Dockerfile -t "$IMAGE" .
buildah tag "$IMAGE" "$TAG"

echo "Built: $TAG"
