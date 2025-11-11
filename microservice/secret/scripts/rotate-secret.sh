#!/usr/bin/env bash
set -euo pipefail

NAME="$1"
NEW_KEY=$(aws secretsmanager create-secret --name "$NAME-new" --secret-string "$(openssl rand -base64 32)" --query SecretId --output text)
aws secretsmanager update-secret --secret-id "$NAME" --secret-string "$(aws secretsmanager get-secret-value --secret-id $NEW_KEY --query SecretString --output text)"
aws secretsmanager delete-secret --secret-id "$NAME-old" --recovery-window-in-days 7 || true
echo "$NEW_KEY"
