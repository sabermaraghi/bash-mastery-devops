#!/usr/bin/env bash
set -euo pipefail

REPORT="log-report-$(date +%Y%m%d).txt"

# Auth log: Debian/Ubuntu uses auth.log, RedHat family uses secure.
AUTH_LOG=""
for candidate in /var/log/auth.log /var/log/secure; do
  [[ -r "$candidate" ]] && {
    AUTH_LOG="$candidate"
    break
  }
done

# System log: Debian/Ubuntu uses syslog, RedHat family uses messages.
SYS_LOG=""
for candidate in /var/log/syslog /var/log/messages; do
  [[ -r "$candidate" ]] && {
    SYS_LOG="$candidate"
    break
  }
done

echo "=== Log Analyzer Report — $(date) ===" >"$REPORT"

echo "" >>"$REPORT"
echo "--- Recent failed logins ---" >>"$REPORT"
if [[ -n "$AUTH_LOG" ]]; then
  echo "(source: $AUTH_LOG)" >>"$REPORT"
  grep "Failed password" "$AUTH_LOG" | tail -10 >>"$REPORT" || echo "No failed logins found" >>"$REPORT"
elif command -v journalctl &>/dev/null; then
  echo "(no auth.log/secure found on disk — falling back to journalctl)" >>"$REPORT"
  journalctl -u ssh -n 10 --no-pager 2>/dev/null | grep "Failed password" >>"$REPORT" || echo "No failed logins found" >>"$REPORT"
else
  echo "No auth log source available on this system" >>"$REPORT"
fi

echo "" >>"$REPORT"
echo "--- Top error/warning keywords ---" >>"$REPORT"
if [[ -n "$SYS_LOG" ]]; then
  echo "(source: $SYS_LOG)" >>"$REPORT"
  grep -iE "(error|fail|warning|critical)" "$SYS_LOG" | cut -d' ' -f5- | sort | uniq -c | sort -nr | head -10 >>"$REPORT" || true
elif command -v journalctl &>/dev/null; then
  echo "(no syslog/messages found on disk — falling back to journalctl)" >>"$REPORT"
  journalctl -p err..alert -n 10 --no-pager >>"$REPORT" 2>/dev/null || true
else
  echo "No system log source available on this system" >>"$REPORT"
fi

echo "Report saved: $REPORT"
