param(
  [ValidateSet('start','stop')]
  [string]$Action = 'start',
  [int]$LocalPort = 3000,
  [int]$RemotePort = 3000,
  [string]$RemoteHost = '158.160.107.227',
  [string]$RemoteUser = 'bender',
  [string]$KeyPath = 'C:\Users\arist\.ssh\ssh-key-1755521373100'
)

function Get-TunnelProcesses {
  $query = "-L $LocalPort:127.0.0.1:$RemotePort"
  Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'ssh.exe' -and $_.CommandLine -like "*${query}*" }
}

if ($Action -eq 'stop') {
  $procs = Get-TunnelProcesses
  if (-not $procs) { Write-Host "No tunnel processes found."; exit 0 }
  foreach ($p in $procs) {
    try {
      Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
      Write-Host "Stopped ssh tunnel PID=$($p.ProcessId)"
    } catch {
      Write-Warning "Failed to stop PID=$($p.ProcessId): $($_.Exception.Message)"
    }
  }
  exit 0
}

# Start
# 1) Check local port availability
$listener = $null
try {
  $listener = [System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse('127.0.0.1'), $LocalPort)
  $listener.Start(); $listener.Stop(); $listener = $null
} catch {
  Write-Error "Local port $LocalPort is already in use. Use -LocalPort to change or stop existing tunnel (use -Action stop)."
  exit 1
}

# 2) Ensure key exists
if (-not (Test-Path -LiteralPath $KeyPath)) {
  Write-Error "Key not found: $KeyPath"; exit 1
}

# 3) Start SSH tunnel
$tunnelArgs = "-N -L $LocalPort:127.0.0.1:$RemotePort -i `"$KeyPath`" $RemoteUser@$RemoteHost"
Write-Host "Starting tunnel: ssh $tunnelArgs"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh'
$psi.Arguments = $tunnelArgs
$psi.CreateNoWindow = $true
$psi.UseShellExecute = $false
$proc = [System.Diagnostics.Process]::Start($psi)
Start-Sleep -Seconds 1

if ($proc.HasExited) {
  Write-Error "SSH exited with code $($proc.ExitCode). Check credentials or connectivity."
  exit $proc.ExitCode
}

# 4) Quick connectivity check
try {
  $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$LocalPort/health" -UseBasicParsing -TimeoutSec 3
  Write-Host "Tunnel is up. Local -> http://127.0.0.1:$LocalPort (HTTP MCP)"
} catch {
  Write-Warning "Tunnel started (PID=$($proc.Id)), but /health is not reachable yet. Validate remote service and firewall."
}
