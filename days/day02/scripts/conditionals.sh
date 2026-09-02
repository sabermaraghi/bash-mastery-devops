#!/usr/bin/env bash
set -euo pipefail

age=25
if [[ $age -gt 18 ]]; then
  echo "You are an adult."
elif [[ $age -eq 18 ]]; then
  echo "You just became an adult."
else
  echo "You are a minor."
fi

# String check
name="Bob"
if [[ -n "$name" ]]; then
  echo "Name is set: $name"
fi
