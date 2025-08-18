#!/usr/bin/env bash
set -euo pipefail

# Installs a systemd service for Issue Monitor
# Usage:
#   sudo ./install-systemd.sh [--name issue-monitor] [--user ubuntu] [--env /path/.env] [--args "--interval=180"]
# Defaults:
#   name: ai-intensive-issue-monitor
#   user: current $SUDO_USER or $USER
#   env:  ./ .env in this directory if exists
#   args: empty (no extra args)

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SERVICE_NAME="ai-intensive-issue-monitor"
RUN_USER="${SUDO_USER:-${USER}}"
ENV_PATH="$SCRIPT_DIR/.env"
EXTRA_ARGS=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      SERVICE_NAME="$2"; shift 2 ;;
    --user)
      RUN_USER="$2"; shift 2 ;;
    --env)
      ENV_PATH="$2"; shift 2 ;;
    --args)
      EXTRA_ARGS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

cat <<UNIT | sudo tee "$UNIT_FILE" > /dev/null
[Unit]
Description=AI Intensive Issue Monitor
After=network.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${SCRIPT_DIR}
Environment=ENV_FILE=${ENV_PATH}
ExecStart=/bin/bash -lc '${SCRIPT_DIR}/start.sh "${ENV_PATH}" -d -- ${EXTRA_ARGS}'
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
