#!/usr/bin/env bash
set -euo pipefail

# Uninstalls a systemd service for MCP Server
# Usage:
#   sudo ./uninstall-systemd.sh [--name ai-intensive-mcp]
# Default name: ai-intensive-mcp

SERVICE_NAME="ai-intensive-mcp"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      SERVICE_NAME="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Stopping and disabling ${SERVICE_NAME}..."
sudo systemctl stop "$SERVICE_NAME" || true
sudo systemctl disable "$SERVICE_NAME" || true

if [[ -f "$UNIT_FILE" ]]; then
  echo "Removing unit file ${UNIT_FILE}"
  sudo rm -f "$UNIT_FILE"
fi

echo "Reloading systemd daemon"
sudo systemctl daemon-reload

echo "Uninstalled ${SERVICE_NAME}."
