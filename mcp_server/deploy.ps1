param(
  [Parameter(Mandatory = $true)]
  [string]$Server,
  [string]$DestPath = "ai-intensive/mcp_server"
)

# Usage examples:
#   powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Server user@host
#   powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Server user@host -DestPath /opt/ai-intensive/mcp_server

$ErrorActionPreference = 'Stop'

# Verify required tools
foreach ($tool in @('ssh','scp')) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    Write-Error "Required tool '$tool' not found in PATH. Install OpenSSH client."
  }
}

# Files to upload (no node_modules)
$files = @(
  'server.js',
  'package.json',
  'package-lock.json',
  'README.md'
) | Where-Object { Test-Path $_ -PathType Leaf }

# Add other .js files in current folder (if any), excluding server.js duplicates
Get-ChildItem -File -Filter *.js | ForEach-Object {
  if ($_.Name -ne 'server.js') {
    if (-not ($files -contains $_.Name)) { $files += $_.Name }
  }
}

# Include start scripts if present
if (Test-Path start.sh -PathType Leaf) { $files += 'start.sh' }
if (Test-Path start.ps1 -PathType Leaf) { $files += 'start.ps1' }
if (Test-Path stop.sh -PathType Leaf) { $files += 'stop.sh' }
if (Test-Path stop.ps1 -PathType Leaf) { $files += 'stop.ps1' }
if (Test-Path install-systemd.sh -PathType Leaf) { $files += 'install-systemd.sh' }
if (Test-Path uninstall-systemd.sh -PathType Leaf) { $files += 'uninstall-systemd.sh' }

Write-Host "Creating remote directory: $Server:$DestPath"
ssh $Server "mkdir -p '$DestPath'"

foreach ($f in $files) {
  Write-Host "Uploading $f -> $Server:$DestPath/"
  scp -q "$f" "$Server:$DestPath/"
}

# Copy .env if present (optional)
if (Test-Path .env -PathType Leaf) {
  Write-Host "Uploading .env -> $Server:$DestPath/.env"
  scp -q ".env" "$Server:$DestPath/.env"
}

Write-Host "Done. Remote path: $Server:$DestPath"
Write-Host "Tip: ssh $Server 'cd $DestPath && npm install && npm start'"
