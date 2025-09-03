param(
  [Parameter(Mandatory=$true)] [string]$IamToken,
  [string]$BodyPath = "tests/body.json",
  [string]$Endpoint = "searchapi.api.cloud.yandex.net:443",
  [string]$Method = "yandex.cloud.searchapi.v2.WebSearchService/Search",
  [string]$OutJson = "tests/result.json",
  [string]$OutXml = "tests/result.xml",
  [string]$FolderId = ""
)

Write-Host "gRPC search via grpcurl"

# Check grpcurl availability
$grpcurl = Get-Command grpcurl -ErrorAction SilentlyContinue
if (-not $grpcurl) {
  Write-Error "grpcurl is not installed or not in PATH. Install from https://github.com/fullstorydev/grpcurl/releases"
  exit 2
}

# Validate token
$IamToken = ($IamToken | Out-String).Trim()
if (-not $IamToken -or $IamToken.Length -eq 0) {
  Write-Error "IamToken is empty. Pass -IamToken '<token>'"
  exit 2
}

# Validate body file
if (-not (Test-Path -Path $BodyPath)) {
  Write-Error "Body file not found: $BodyPath"
  exit 2
}

# Run grpcurl request
$absBody = (Resolve-Path -Path $BodyPath).Path
Write-Host "Running: type '$absBody' | grpcurl -H 'Authorization: Bearer ***' -H 'x-folder-id: <maybe>' -d @ $Endpoint $Method > $OutJson"
try {
  $env:GRPC_VERBOSITY = "ERROR"
  $env:GRPC_TRACE = ""
  $args = @(
    '-H', ("Authorization: Bearer " + $IamToken)
  )
  if ($FolderId -and $FolderId.Trim().Length -gt 0) {
    $args += @('-H', ("x-folder-id: " + ($FolderId.Trim())))
  }
  $args += @(
    '-d', '@',
    '--',
    $Endpoint,
    $Method
  )
  Write-Host ("Args (count=" + $args.Count + "): " + ($args -join " | "))
  # Invoke directly; capture stdout and stderr together
  $jsonIn = Get-Content -Path $absBody -Raw -Encoding UTF8
  $output = $jsonIn | & $grpcurl.Path @args 2>&1
  $exitCode = $LASTEXITCODE
  if ($output) { $output | Write-Host }
  if ($exitCode -ne 0) {
    Write-Error "grpcurl exited with code $exitCode"
    exit $exitCode
  }
  $dir = Split-Path -Parent $OutJson
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  # When output is an array of lines, join to a single JSON string
  $jsonOut = if ($output -is [array]) { ($output -join "`n") } else { [string]$output }
  Set-Content -Path $OutJson -Value $jsonOut -Encoding UTF8
  Write-Host "Saved JSON to: $OutJson"
}
catch {
  Write-Error $_
  exit 1
}

# Decode rawData (Base64) to XML/HTML
try {
  $jsonText = Get-Content -Path $OutJson -Raw -ErrorAction Stop
  $obj = $jsonText | ConvertFrom-Json -ErrorAction Stop
  if (-not $obj.rawData) {
    Write-Warning "rawData not found in result.json. Nothing to decode."
    exit 0
  }
  $bytes = [System.Convert]::FromBase64String($obj.rawData)
  $dir2 = Split-Path -Parent $OutXml
  if ($dir2 -and -not (Test-Path $dir2)) { New-Item -ItemType Directory -Path $dir2 | Out-Null }
  [System.IO.File]::WriteAllBytes($OutXml, $bytes)
  Write-Host "Decoded to: $OutXml"
}
catch {
  Write-Error "Failed to decode rawData: $_"
  exit 1
}
