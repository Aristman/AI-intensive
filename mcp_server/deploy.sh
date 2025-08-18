#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./deploy.sh user@host [dest_path]
#
# Copies MCP server files to remote server into ai-intensive/mcp_server (default dest)
# Requires ssh/scp available locally and on the remote side.

SERVER_ADDR=${1:-}
DEST_PATH=${2:-ai-intensive/mcp_server}

if [[ -z "$SERVER_ADDR" ]]; then
  echo "Usage: $0 user@host [dest_path]"
  exit 1
fi

# Files to upload (no node_modules)
FILES=(
  "server.js"
  "package.json"
  "package-lock.json"
  "README.md"
)

# Add all .js files in current directory (if any), avoiding duplicates
for f in ./*.js; do
  [[ -e "$f" ]] || continue
  [[ "$f" == "./server.js" ]] && continue
  FILES+=("${f#./}")
done

# Create remote dir
ssh "$SERVER_ADDR" "mkdir -p '$DEST_PATH'"

# Copy files
for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    echo "Uploading $f -> $SERVER_ADDR:$DEST_PATH/"
    scp -q "$f" "$SERVER_ADDR:$DEST_PATH/"
  fi
done

echo "Done. Remote path: $SERVER_ADDR:$DEST_PATH"
echo "Tip: ssh $SERVER_ADDR 'cd $DEST_PATH && npm install && npm start'"
