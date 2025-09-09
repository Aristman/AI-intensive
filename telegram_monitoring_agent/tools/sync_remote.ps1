#!/usr/bin/env pwsh
<#!
.SYNOPSIS
  Simple file sync: copy/update project files to a remote Linux server via SSH (no systemd, no installs).

.PARAMETER Remote
  SSH target in the form user@host

.PARAMETER RemoteDir
  Target directory on remote host (e.g. /opt/ai-intensive or /home/user/ai-intensive)

.PARAMETER KeyPath
  Optional path to SSH private key

.EXAMPLE
  pwsh -File tools/sync_remote.ps1 -Remote user@host -RemoteDir /home/user/ai-intensive
  pwsh -File tools/sync_remote.ps1 -Remote user@host -RemoteDir /opt/ai-intensive -KeyPath C:\Users\me\.ssh\id_rsa

.NOTES
  Requirements:
   - Local: PowerShell 7+, tar, ssh, scp
   - Remote: Linux with tar; write access to RemoteDir
#>

param(
  [Parameter(Mandatory=$true)] [string]$Remote,
  [Parameter(Mandatory=$true)] [string]$RemoteDir,
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

# Paths to sync
$Include = @(
  'telegram_monitoring_agent',
  'mcp_servers/yandex_search_mcp_server',
  'mcp_servers/telegram_mcp_server_py'
)

# Create temp working area
$Temp = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "ai_sync_" + [System.Guid]::NewGuid().ToString('N'))) -Force
$ArchivePath = Join-Path $Temp 'sync.tar.gz'
$Stage = Join-Path $Temp 'stage'
New-Item -ItemType Directory -Path $Stage | Out-Null

Write-Host "==> Staging files for sync"
foreach ($p in $Include) {
  $src = Join-Path $RootDir $p
  $dst = Join-Path $Stage $p
  Write-Host "    - $p"
  robocopy $src $dst * /E /XF '.env' /XD '__pycache__' '.venv' 'node_modules' 'logs' | Out-Null
}

Write-Host "==> Creating archive $ArchivePath"
Push-Location $Stage
try {
  tar -czf $ArchivePath *
}
finally { Pop-Location }

# Upload to /tmp
Write-Host "==> Uploading archive to remote /tmp"
if ($KeyPath) {
  scp -o StrictHostKeyChecking=no -i "$KeyPath" $ArchivePath "${Remote}:/tmp/ai_sync.tar.gz"
} else {
  scp -o StrictHostKeyChecking=no $ArchivePath "${Remote}:/tmp/ai_sync.tar.gz"
}

# Remote unpack (no sudo; ensure dir exists under user perms)
$remoteScript = @'
set -euo pipefail
REMOTE_DIR="$1"
mkdir -p "$REMOTE_DIR"
cd "$REMOTE_DIR"
if [ -f /tmp/ai_sync.tar.gz ]; then
  tar -xzf /tmp/ai_sync.tar.gz -C "$REMOTE_DIR"
  rm -f /tmp/ai_sync.tar.gz
fi
# Show result tree (top level only)
ls -la "$REMOTE_DIR"
'@

Write-Host "==> Applying sync on remote"
$remoteArgs = "'$RemoteDir'"
$sshPipeArgs = @('-tt')
if ($KeyPath) { $sshPipeArgs += @('-i', $KeyPath) }
$sshPipeArgs += @($Remote, "bash -s -- $remoteArgs")
$remoteScript | ssh @sshPipeArgs

Write-Host "==> Sync complete"
