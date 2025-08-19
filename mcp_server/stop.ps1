# Stops MCP server using PID from mcp_server.pid
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $scriptDir 'mcp_server.pid'

if (-not (Test-Path $pidFile -PathType Leaf)) {
  Write-Error "PID file not found: $pidFile"
}
$pid = Get-Content $pidFile | Select-Object -First 1
try {
  $proc = Get-Process -Id $pid -ErrorAction Stop
  Write-Host "Stopping MCP server PID=$pid"
  $proc.CloseMainWindow() | Out-Null
  Start-Sleep -Seconds 1
  if (!$proc.HasExited) { $proc.Kill() }
  Write-Host "Stopped."
} catch {
  Write-Host "Process $pid not running. Removing PID file."
}
Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
