#!/usr/bin/env bash
# Mini-project: decide access from a name + age passed on the command line.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 NAME AGE"
  exit 1
fi

name="$1"
age="$2"

if [[ ! "$age" =~ ^[0-9]+$ ]]; then
  echo "AGE must be a number, got: $age"
  exit 1
fi

if [[ $age -ge 18 ]]; then
  echo "Welcome, $name!"
else
  echo "Access denied."
fi
