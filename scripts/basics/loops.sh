#!/bin/bash
set -euo pipefail

# For loops
for fruit in apple banana cherry date; do
  echo "I like $fruit"
done



for file in scripts/basics/day2/*.sh; do
  echo "Found script: $file"
done



for ((i=1; i<=5; i++)); do
  echo "Count: $i"
done


# While loops
count=1
while [ $count -le 5 ]; do
  echo "While count: $count"
  ((count++))
done


while IFS= read -r line; do
  echo "Line: $line"
done < README.md


# Until loop
seconds=0
until [ $seconds -ge 3 ]; do
  echo "Waiting... $seconds seconds"
  sleep 1
  ((seconds++))
done

