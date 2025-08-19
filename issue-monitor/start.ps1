param(
  [string]$EnvPath = "",
  [switch]$Background,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ArgsRest
)

# Usage examples:
#   powershell -ExecutionPolicy Bypass -File .\start.ps1                      # uses .\.env
#   powershell -ExecutionPolicy Bypass -File .\start.ps1 -EnvPath .\.env -- --interval=180
#   powershell -ExecutionPolicy Bypass -File .\start.ps1 -- --interval=180     # no env path, just args to jar

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) {
  $EnvPath = Join-Path $scriptDir ".env"
}

if (Test-Path $EnvPath -PathType Leaf) {
  Write-Host "Loading environment from: $EnvPath"
  # Naive loader: parse KEY=VALUE lines
  Get-Content $EnvPath | ForEach-Object {
    if ($_ -match '^[#;]') { return }
    if ($_ -notmatch '=') { return }
    $parts = $_.Split('=',2)
    $key = $parts[0].Trim()
    $val = $parts[1]
    if (-not [string]::IsNullOrWhiteSpace($key)) { $env:$key = $val }
  }
} else {
  Write-Host "No .env found at: $EnvPath (skipping)"
}

# Find latest fat jar
$jarFiles = Get-ChildItem -File -Path (Join-Path $scriptDir 'build\libs') -Filter '*-all.jar' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if (-not $jarFiles -or $jarFiles.Count -eq 0) {
  Write-Error "Fat JAR not found in build/libs. Build first: .\\gradlew.bat :issue-monitor:build"
}
$jar = $jarFiles[0].FullName

Push-Location $scriptDir
if ($Background.IsPresent) {
  Write-Host "Starting in background -> issue-monitor.log"
  $argList = @('-jar', $jar) + $ArgsRest
  $p = Start-Process java -ArgumentList $argList -WorkingDirectory $scriptDir -RedirectStandardOutput (Join-Path $scriptDir 'issue-monitor.log') -RedirectStandardError (Join-Path $scriptDir 'issue-monitor.log') -PassThru -WindowStyle Hidden
  Set-Content -Path (Join-Path $scriptDir 'issue-monitor.pid') -Value $p.Id
  Write-Host "Started. PID=$($p.Id)"
} else {
  Write-Host "Starting: java -jar $jar $($ArgsRest -join ' ')"
  & java -jar $jar @ArgsRest
}
Pop-Location
