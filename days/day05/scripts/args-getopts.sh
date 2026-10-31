#!/usr/bin/env bash
# Named flags with getopts:  -e ENV  -v  -h
set -euo pipefail

env="staging"
verbose=false

usage() {
  cat <<USAGE
Usage: $0 [-e ENV] [-v] [-h]
  -e ENV   target environment (default: staging)
  -v       verbose output
  -h       show this help
USAGE
}

while getopts ":e:vh" opt; do
  case "$opt" in
    e) env="$OPTARG" ;;
    v) verbose=true ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
    \?)
      echo "Unknown option: -$OPTARG" >&2
      usage
      exit 1
      ;;
  esac
done

echo "Environment: $env"
$verbose && echo "Verbose mode is ON"
