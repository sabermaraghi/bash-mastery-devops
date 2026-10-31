#!/usr/bin/env bash
# File: scripts/advanced/day9/app.sh
# Purpose: Tiny consumer that shows config-loader.sh in action.
#
# The point of Day 9: app.sh sources the loader so the validated, exported
# config lands in *this* process's environment.
set -euo pipefail

# Resolve the loader relative to this file, not the current working directory.
# The old version hardcoded `./scripts/advanced/day9/config-loader.sh`, which
# only worked when you happened to run it from the repo root and broke from
# anywhere else.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/advanced/day9/config-loader.sh
source "$SCRIPT_DIR/config-loader.sh"

echo "Connecting to $TARGET_HOST:$TARGET_PORT as $APP_ENV ..."
echo "API call authorized (key present: ${API_KEY:+yes})"
