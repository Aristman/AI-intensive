#!/usr/bin/env pwsh
<#!
.SYNOPSIS
  Deploy telegram_monitoring_agent and Yandex Search MCP bridge to a remote Linux server (PowerShell).

.PARAMETER Remote
  SSH target in the form user@host

.PARAMETER RemoteDir
  Target directory on remote host (e.g. /opt/ai-intensive)

.PARAMETER BridgePort
  WebSocket bridge port (default 8765)

.PARAMETER PythonBin
  Python binary on remote (default: python3)

.PARAMETER NodeBin
  Node binary on remote (default: node)

.EXAMPLE
  pwsh -File tools/deploy_remote.ps1 -Remote user@host -RemoteDir /opt/ai-intensive

.NOTES
  Requirements:
   - Local: PowerShell 7+, tar, ssh, scp
   - Remote: Linux with Python 3.10+, Node.js 18+, systemd
#>

param(
  [Parameter(Mandatory=$true)] [string]$Remote,
  [Parameter(Mandatory=$true)] [string]$RemoteDir,
  [int]$BridgePort = 8765,
  [string]$PythonBin = 'python3',
  [string]$NodeBin = 'node',
  [string]$KeyPath
)

$ErrorActionPreference = 'Stop'

function Invoke-Remote {
  param([string]$Command)
  $sshArgs = @('-o','StrictHostKeyChecking=no')
  if ($KeyPath) { $sshArgs += @('-i', $KeyPath) }
  $sshArgs += @($Remote, $Command)
  ssh @sshArgs
}

# Resolve repo root (this script lives in telegram_monitoring_agent/tools)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = Resolve-Path (Join-Path $ScriptDir '..' | Join-Path -ChildPath '..')

# Paths
$TgAgentDir    = Join-Path $RootDir 'telegram_monitoring_agent'
$McpYandexDir  = Join-Path $RootDir 'mcp_servers' | Join-Path -ChildPath 'yandex_search_mcp_server'
$McpTgPyDir    = Join-Path $RootDir 'mcp_servers' | Join-Path -ChildPath 'telegram_mcp_server_py'

# Create temporary archive excluding heavy/ephemeral dirs
$Temp = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ai_deploy_" + [System.Guid]::NewGuid().ToString('N'))) -Force
$ArchivePath = Join-Path $Temp 'deploy.tar.gz'

Write-Host "==> Preparing deploy archive at $ArchivePath"
# Build a staging directory to control excludes
$Stage = Join-Path $Temp 'stage'
New-Item -ItemType Directory -Path $Stage | Out-Null

# Copy subsets with excludes
Write-Host "    - Staging telegram_monitoring_agent"
robocopy $TgAgentDir (Join-Path $Stage 'telegram_monitoring_agent') * /E /XD '__pycache__' '.venv' 'node_modules' 'logs' | Out-Null

Write-Host "    - Staging mcp_servers/yandex_search_mcp_server"
robocopy $McpYandexDir (Join-Path $Stage 'mcp_servers\yandex_search_mcp_server') * /E /XD 'node_modules' /XF '.env' | Out-Null

Write-Host "    - Staging mcp_servers/telegram_mcp_server_py"
robocopy $McpTgPyDir (Join-Path $Stage 'mcp_servers\telegram_mcp_server_py') * /E /XD '__pycache__' '.venv' /XF '.env' | Out-Null

# Create archive
Push-Location $Stage
try {
  # Use tar available on Windows 10+ (bsdtar)
  tar -czf $ArchivePath *
}
finally { Pop-Location }

# Ensure remote dir exists
Write-Host "==> Creating remote dir ${Remote}:$RemoteDir"
Invoke-Remote "mkdir -p $RemoteDir"

# Copy archive to a writable temp location on remote
Write-Host "==> Uploading archive"
if ($KeyPath) {
  scp -o StrictHostKeyChecking=no -i "$KeyPath" $ArchivePath "${Remote}:/tmp/deploy.tar.gz"
} else {
  scp -o StrictHostKeyChecking=no $ArchivePath "${Remote}:/tmp/deploy.tar.gz"
}

# Remote installation script
$remoteScript = @'
set -euo pipefail
REMOTE_DIR="$1"
BRIDGE_PORT="$2"
PYTHON_BIN="$3"
NODE_BIN="$4"

# Ensure target directory exists and is owned by current user
U="$(whoami)"
if [ ! -d "$REMOTE_DIR" ]; then
  sudo mkdir -p "$REMOTE_DIR"
fi
sudo chown -R "$U":"$U" "$REMOTE_DIR" || true

cd "$REMOTE_DIR"

# Unpack payload
if [ -f /tmp/deploy.tar.gz ]; then
  mv /tmp/deploy.tar.gz "$REMOTE_DIR/deploy.tar.gz"
fi
if [ -f "$REMOTE_DIR/deploy.tar.gz" ]; then
  tar -xzf "$REMOTE_DIR/deploy.tar.gz"
  rm -f "$REMOTE_DIR/deploy.tar.gz"
fi

# 1) Python venv and deps
if [ ! -d "$REMOTE_DIR/venv" ]; then
  "$PYTHON_BIN" -m venv venv
fi
. "$REMOTE_DIR/venv/bin/activate"
pip install --upgrade pip
pip install -r telegram_monitoring_agent/requirements.txt
pip install -r mcp_servers/telegram_mcp_server_py/requirements.txt || true
deactivate

# 2) Node deps for Yandex Search MCP + bridge
cd "$REMOTE_DIR/mcp_servers/yandex_search_mcp_server"
if [ -f package-lock.json ]; then
  npm ci --silent
else
  npm install --silent
fi
cd bridge
if [ -f package-lock.json ]; then
  npm ci --silent
else
  npm install --silent
fi

# 3) systemd units
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

[Install]
WantedBy=multi-user.target
UNIT

sudo mv ai-telegram-agent.service /etc/systemd/system/
sudo mv ai-yandex-search-bridge.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ai-yandex-search-bridge.service ai-telegram-agent.service

if [ -f "${REMOTE_DIR}/mcp_servers/yandex_search_mcp_server/.env" ]; then
  sudo systemctl restart ai-yandex-search-bridge.service || true
else
  echo "[WARN] ${REMOTE_DIR}/mcp_servers/yandex_search_mcp_server/.env not found. Create it with YANDEX_API_KEY and YANDEX_FOLDER_ID before starting the bridge." >&2
fi

sudo systemctl restart ai-telegram-agent.service || true

systemctl --no-pager -l status ai-yandex-search-bridge.service || true
systemctl --no-pager -l status ai-telegram-agent.service || true
'@

# Execute remote script (pipe via stdin to avoid complex quoting)
Write-Host "==> Configuring remote"
$remoteArgs = "'$RemoteDir' '$BridgePort' '$PythonBin' '$NodeBin'"
$sshPipeArgs = @('-tt')
if ($KeyPath) { $sshPipeArgs += @('-i', $KeyPath) }
$sshPipeArgs += @($Remote, "bash -s -- $remoteArgs")
$remoteScript | ssh @sshPipeArgs

Write-Host "==> Deployment complete"
