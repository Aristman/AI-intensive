#!/usr/bin/env bash
set -euo pipefail

# Installs a systemd service for MCP Server
# Usage:
#   sudo ./install-systemd.sh [--name mcp-server] [--user ubuntu] [--env /path/.env]
# Defaults:
#   name: ai-intensive-mcp
#   user: current $SUDO_USER or $USER
#   env:  ./ .env in this directory if exists

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SERVICE_NAME="ai-intensive-mcp"
RUN_USER="${SUDO_USER:-${USER}}"
ENV_PATH="$SCRIPT_DIR/.env"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      SERVICE_NAME="$2"; shift 2 ;;
    --user)
      RUN_USER="$2"; shift 2 ;;
    --env)
      ENV_PATH="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

cat <<UNIT | sudo tee "$UNIT_FILE" > /dev/null
[Unit]
Description=AI Intensive MCP Server
After=network.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${SCRIPT_DIR}
Environment=DOTENV_CONFIG_PATH=${ENV_PATH}
ExecStart=/bin/bash -lc '${SCRIPT_DIR}/start.sh -d'
ExecStop=/bin/bash -lc '${SCRIPT_DIR}/stop.sh'
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE_NAME"
echo "Installed and started service: $SERVICE_NAME"
echo "Manage with: systemctl status $SERVICE_NAME | stop | restart | disable"
