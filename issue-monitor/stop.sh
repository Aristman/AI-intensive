#!/usr/bin/env bash
set -euo pipefail

# Stops Issue Monitor using PID from issue-monitor.pid
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PID_FILE="$SCRIPT_DIR/issue-monitor.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "PID file not found: $PID_FILE"
  exit 1
fi
PID=$(cat "$PID_FILE")
if ! kill -0 "$PID" 2>/dev/null; then
  echo "Process $PID not running. Removing PID file."
  rm -f "$PID_FILE"
  exit 0
fi

echo "Stopping Issue Monitor PID=$PID"
kill "$PID"
# Wait up to 10s
for i in {1..10}; do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Stopped."
    rm -f "$PID_FILE"
    exit 0
  fi
  sleep 1
 done

echo "Force killing PID=$PID"
kill -9 "$PID" || true
rm -f "$PID_FILE"
echo "Stopped."
