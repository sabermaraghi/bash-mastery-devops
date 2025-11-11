#!/usr/bin/env bash
set -euo pipefail

IMAGE="localhost/cost-api:v1.0.0"
TAG="ghcr.io/yourusername/cost-api:v1.0.0"

buildah bud -f docker/Dockerfile -t "$IMAGE" .
buildah tag "$IMAGE" "$TAG"

echo "Built: $TAG"
