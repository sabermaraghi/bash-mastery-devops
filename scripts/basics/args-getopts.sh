#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 -n NAME -a AGE [-v]"
  echo "Example: $0 -n Ali -a 25 -v"
  exit 1
}

verbose=0
while getopts "n:a:v" opt; do
  case $opt in
    n) name="$OPTARG" ;;
    a) age="$OPTARG" ;;
    v) verbose=1 ;;
    *) usage ;;
  esac
done

[[ -z "${name:-}" || -z "${age:-}" ]] && usage

echo "Name: $name, Age: $age"
(( verbose )) && echo "Verbose mode enabled"




#!/bin/bash
#set -euo pipefail

#usage() {
#  echo "Usage: $0 -n NAME -a AGE [-v]"
#  exit 1
#}

#verbose=0
#while getopts "n:a:v" opt; do
#  case $opt in
#    n) name="$OPTARG" ;;
#    a) age="$OPTARG" ;;
#    v) verbose=1 ;;
#    *) usage ;;
#  esac
#done

#[[ -z "$name" || -z "$age" ]] && usage

#echo "Name: $name, Age: $age"
#((verbose)) && echo "Verbose mode enabled"
