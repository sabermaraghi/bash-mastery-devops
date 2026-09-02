#!/usr/bin/env bash
set -euo pipefail

echo "=== User Report - $(date) ==="
echo "Total users: $(wc -l </etc/passwd)"
echo

echo "Users with /bin/bash:"
grep "/bin/bash" /etc/passwd | awk -F: '{print $1, $6}' | column -t

echo -e "\nLast login times:"
if command -v journalctl &>/dev/null; then
  journalctl _COMM=sshd 2>/dev/null | tail -20
elif command -v lastlog &>/dev/null; then
  lastlog -u 1000-60000 | tail -20
else
  echo "No login-history tool available on this system"
fi
