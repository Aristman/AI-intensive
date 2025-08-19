#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./start.sh [env_path] [--daemon|-d]
# If env_path not provided, uses ./.env in this directory.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
ENV_PATH="$SCRIPT_DIR/.env"
DAEMON=false

# Parse optional env_path (first arg that doesn't start with '-')
if [[ ${1-} && ! ${1-} =~ ^- ]]; then
  ENV_PATH="$1"
  shift
fi

# Parse flags
if [[ ${1-} == "--daemon" || ${1-} == "-d" ]]; then
  DAEMON=true
  shift || true
fi

export DOTENV_CONFIG_PATH="$ENV_PATH"

echo "Using DOTENV_CONFIG_PATH=$DOTENV_CONFIG_PATH"
# Install deps if missing
if [[ ! -d "$SCRIPT_DIR/node_modules" ]]; then
  echo "node_modules not found, running npm install..."
  (cd "$SCRIPT_DIR" && npm install)
fi

# Start server
cd "$SCRIPT_DIR"
if [[ "$DAEMON" == true ]]; then
  echo "Starting in background (nohup) -> mcp_server.log"
  nohup npm start > mcp_server.log 2>&1 & echo $! > mcp_server.pid
  disown || true
  echo "Started. PID=$(cat mcp_server.pid)"
  exit 0
else
  exec npm start
fi
