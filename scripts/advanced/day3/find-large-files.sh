#!/bin/bash
set -euo pipefail

SIZE="100M"
DIR="${1:-/home}"

echo "Finding files larger than $SIZE in $DIR ..."
echo "============================================"

find "$DIR" -type f -size +$SIZE -exec du -h {} \; | sort -hr | head -20
