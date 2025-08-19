param(
  [string]$EnvPath = "",
  [switch]$Background
)

# Usage examples:
#   powershell -ExecutionPolicy Bypass -File .\start.ps1              # uses .\.env
#   powershell -ExecutionPolicy Bypass -File .\start.ps1 -EnvPath C:\path\to\.env

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) {
  $EnvPath = Join-Path $scriptDir ".env"
}

$env:DOTENV_CONFIG_PATH = $EnvPath
Write-Host "Using DOTENV_CONFIG_PATH=$($env:DOTENV_CONFIG_PATH)"

# Install dependencies if node_modules missing
if (-not (Test-Path (Join-Path $scriptDir 'node_modules'))) {
  Write-Host "node_modules not found, running npm install..."
  Push-Location $scriptDir
  npm install
  Pop-Location
}

Push-Location $scriptDir
if ($Background.IsPresent) {
  Write-Host "Starting in background -> mcp_server.log"
  $p = Start-Process npm -ArgumentList 'start' -WorkingDirectory $scriptDir -RedirectStandardOutput (Join-Path $scriptDir 'mcp_server.log') -RedirectStandardError (Join-Path $scriptDir 'mcp_server.log') -PassThru -WindowStyle Hidden
  Set-Content -Path (Join-Path $scriptDir 'mcp_server.pid') -Value $p.Id
  Write-Host "Started. PID=$($p.Id)"
} else {
  npm start
}
Pop-Location
