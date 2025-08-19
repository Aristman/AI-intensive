#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./start.sh [env_path] [--daemon|-d] [-- java args...]
# If env_path not provided, uses ./.env in this directory.
# Any extra args are passed to the Java app (e.g., --interval=180)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ENV_PATH="$SCRIPT_DIR/.env"
DAEMON=false

# If first arg is non-flag, treat it as env path
if [[ ${1-} && ! ${1-} =~ ^- ]]; then
  ENV_PATH="$1"
  shift
fi

# Optional daemon flag
if [[ ${1-} == "--daemon" || ${1-} == "-d" ]]; then
  DAEMON=true
  shift || true
fi

# Load .env if present
if [[ -f "$ENV_PATH" ]]; then
  echo "Loading environment from: $ENV_PATH"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_PATH"
  set +a
else
  echo "No .env found at: $ENV_PATH (skipping)"
fi

# Find latest fat jar
JAR=$(ls -t "$SCRIPT_DIR"/*-all.jar 2>/dev/null | head -n1 || true)
if [[ -z "${JAR}" ]]; then
  echo "Fat JAR not found. Build first: ./gradlew :issue-monitor:build" >&2
  exit 2
fi

# Determine extra args (skip env_path if provided)
EXTRA_ARGS=()
if [[ ${1-} =~ ^/|^[A-Za-z]:|^\. ]]; then
  # first arg was env path; pass the rest
  shift || true
fi
# pass remaining args
if [[ $# -gt 0 ]]; then
  EXTRA_ARGS=("$@")
fi

cd "$SCRIPT_DIR"
if [[ "$DAEMON" == true ]]; then
  echo "Starting in background (nohup) -> issue-monitor.log"
  nohup java -jar "$JAR" "${EXTRA_ARGS[@]}" > issue-monitor.log 2>&1 & echo $! > issue-monitor.pid
  disown || true
  echo "Started. PID=$(cat issue-monitor.pid)"
  exit 0
else
  echo "Starting: java -jar $JAR ${EXTRA_ARGS[*]-}"
  exec java -jar "$JAR" "${EXTRA_ARGS[@]}"
fi
