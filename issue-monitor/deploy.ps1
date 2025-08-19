param(
  [Parameter(Mandatory = $true)]
  [string]$Server,
  [string]$DestPath = "ai-intensive/issue-monitor"
)

# Usage examples:
#   powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Server user@host
#   powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Server user@host -DestPath /opt/ai-intensive/issue-monitor

$ErrorActionPreference = 'Stop'

foreach ($tool in @('ssh','scp')) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    Write-Error "Required tool '$tool' not found in PATH. Install OpenSSH client."
  }
}

# Find latest fat jar
$jarFiles = Get-ChildItem -File -Path "build/libs" -Filter "*-all.jar" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if (-not $jarFiles -or $jarFiles.Count -eq 0) {
  Write-Error "Fat JAR not found in build/libs. Build first: .\\gradlew.bat :issue-monitor:build"
}
$jar = $jarFiles[0].FullName

$files = @($jar)
if (Test-Path README.md -PathType Leaf) { $files += 'README.md' }
if (Test-Path config.properties -PathType Leaf) { $files += 'config.properties' }
if (Test-Path .env -PathType Leaf) { $files += '.env' }
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

$base = Split-Path -Leaf $jar
Write-Host "Done. Remote path: $Server:$DestPath"
Write-Host "Tip: ssh $Server 'cd $DestPath && nohup java -jar $base > app.log 2>&1 & disown'"
