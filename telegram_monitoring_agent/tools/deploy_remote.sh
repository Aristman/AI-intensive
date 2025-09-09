#!/usr/bin/env bash
# Deploy telegram_monitoring_agent and Yandex Search MCP bridge to a remote Linux server
# Requirements on local: rsync, ssh
# Requirements on remote: Python 3.10+, venv, Node.js 18+, systemd
# Usage:
#   chmod +x tools/deploy_remote.sh
#   tools/deploy_remote.sh <user>@<host> /opt/ai-intensive
# Optional env:
#   BRIDGE_PORT=8765  (default)
#   PYTHON_BIN=python3 (default)
#   NODE_BIN=node      (default)
set -euo pipefail

REMOTE=${1:-}
REMOTE_DIR=${2:-}
if [[ -z "${REMOTE}" || -z "${REMOTE_DIR}" ]]; then
  echo "Usage: $0 <user>@<host> <remote_dir>" >&2
  exit 1
fi

BRIDGE_PORT=${BRIDGE_PORT:-8765}
PYTHON_BIN=${PYTHON_BIN:-python3}
NODE_BIN=${NODE_BIN:-node}

# Project root (this script is under telegram_monitoring_agent/tools)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Paths to deploy
TG_AGENT_DIR="telegram_monitoring_agent"
MCP_YANDEX_DIR="mcp_servers/yandex_search_mcp_server"
MCP_TG_PY_DIR="mcp_servers/telegram_mcp_server_py"

echo "==> Creating directories on remote: ${REMOTE}:${REMOTE_DIR}"
ssh -o StrictHostKeyChecking=no "${REMOTE}" "mkdir -p ${REMOTE_DIR}" >/dev/null

echo "==> Rsync project subsets to remote"
rsync -az --delete \
  --exclude "__pycache__/" \
  --exclude ".venv/" \
  --exclude "node_modules/" \
  --exclude "logs/" \
  "${ROOT_DIR}/${TG_AGENT_DIR}" "${REMOTE}:${REMOTE_DIR}/"

rsync -az --delete \
  --exclude "node_modules/" \
  --exclude ".env" \
  "${ROOT_DIR}/${MCP_YANDEX_DIR}" "${REMOTE}:${REMOTE_DIR}/mcp_servers/"

rsync -az --delete \
  --exclude "__pycache__/" \
  --exclude ".venv/" \
  --exclude ".env" \
  "${ROOT_DIR}/${MCP_TG_PY_DIR}" "${REMOTE}:${REMOTE_DIR}/mcp_servers/"

REMOTE_SH=$(cat <<'EOS'
set -euo pipefail
REMOTE_DIR="$1"
BRIDGE_PORT="$2"
PYTHON_BIN="$3"
NODE_BIN="$4"
cd "$REMOTE_DIR"

# 1) Python venv and deps for telegram_monitoring_agent and telegram_mcp_server_py
if [[ ! -d "${REMOTE_DIR}/venv" ]]; then
  "$PYTHON_BIN" -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip
pip install -r telegram_monitoring_agent/requirements.txt
# Telegram MCP (python) deps (used as stdio child)
pip install -r mcp_servers/telegram_mcp_server_py/requirements.txt || true

deactivate

# 2) Node deps for Yandex Search MCP + bridge
cd "$REMOTE_DIR/mcp_servers/yandex_search_mcp_server"
if [[ -f package-lock.json ]]; then
  npm ci --silent
else
  npm install --silent
fi
cd bridge
if [[ -f package-lock.json ]]; then
  npm ci --silent
else
  npm install --silent
fi

# 3) systemd unit files
cd "$REMOTE_DIR"
cat > ai-telegram-agent.service <<UNIT
[Unit]
Description=AI Telegram Monitoring Agent
After=network.target

[Service]
Type=simple
WorkingDirectory=${REMOTE_DIR}
ExecStart=${REMOTE_DIR}/venv/bin/python -u telegram_monitoring_agent/main.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
# Add any required env here, or use /etc/systemd/system/ai-telegram-agent.service.d/override.conf

[Install]
WantedBy=multi-user.target
UNIT

cat > ai-yandex-search-bridge.service <<UNIT
[Unit]
Description=Yandex Search MCP WS Bridge
After=network.target

[Service]
Type=simple
WorkingDirectory=${REMOTE_DIR}/mcp_servers/yandex_search_mcp_server/bridge
ExecStart=${NODE_BIN} ${REMOTE_DIR}/mcp_servers/yandex_search_mcp_server/bridge/ws_stdio_bridge.js
Restart=always
RestartSec=5
Environment=BRIDGE_PORT=${BRIDGE_PORT}
# The bridge spawns STDIO server one level up. Put Yandex creds into ${REMOTE_DIR}/mcp_servers/yandex_search_mcp_server/.env

[Install]
WantedBy=multi-user.target
UNIT

sudo mv ai-telegram-agent.service /etc/systemd/system/
sudo mv ai-yandex-search-bridge.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ai-yandex-search-bridge.service ai-telegram-agent.service

# Do not start bridge if .env with Yandex creds is missing; print hint instead
if [[ -f "${REMOTE_DIR}/mcp_servers/yandex_search_mcp_server/.env" ]]; then
  sudo systemctl restart ai-yandex-search-bridge.service || true
else
  echo "[WARN] ${REMOTE_DIR}/mcp_servers/yandex_search_mcp_server/.env not found. Create it with YANDEX_API_KEY and YANDEX_FOLDER_ID before starting the bridge." >&2
fi

sudo systemctl restart ai-telegram-agent.service || true

# Print statuses
systemctl --no-pager -l status ai-yandex-search-bridge.service || true
systemctl --no-pager -l status ai-telegram-agent.service || true
EOS
)

echo "==> Configuring remote services and dependencies"
ssh -tt "${REMOTE}" "bash -lc '$REMOTE_SH "$REMOTE_DIR" "$BRIDGE_PORT" "$PYTHON_BIN" "$NODE_BIN"'"

echo "==> Deployment complete"
