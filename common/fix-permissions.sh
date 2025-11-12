#!/usr/bin/env bash
set -euo pipefail

echo "Fixing permissions for all .sh files..."
find . -name "*.sh" -type f -exec chmod +x {} \;

echo "Permissions fixed:"
find . -name "*.sh" -type f -exec ls -la {} \; | head -20
