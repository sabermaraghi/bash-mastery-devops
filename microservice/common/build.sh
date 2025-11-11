#!/usr/bin/env bash
set -euo pipefail
SERVICE="$1"
IMAGE="localhost/$SERVICE-api:latest"
CONTAINER=$(buildah from python:3.12-slim)

buildah copy "$CONTAINER" "../$SERVICE/api/main.py" /app/main.py
buildah copy "$CONTAINER" "../$SERVICE/api/requirements.txt" /app/requirements.txt
buildah copy "$CONTAINER" "../$SERVICE/scripts" /app/scripts/
buildah run "$CONTAINER" -- pip install -r /app/requirements.txt

buildah config --cmd '["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]' "$CONTAINER"
buildah commit "$CONTAINER" "$IMAGE"
echo "Built: $IMAGE"
