#!/bin/bash
set -euo pipefail

VERSION="v1.0.0"
ZIP="microservices-platform-$VERSION.zip"

echo "Building release $VERSION..."
zip -r "$ZIP" \
  microservice/ \
  charts/ \
  argocd/ \
  .github/ \
  scripts/ \
  README.md \
  LICENSE

echo "Release ready: $ZIP"
