#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./deploy.sh user@host [dest_path]
#
# Copies Issue Monitor fat-jar and configs to remote server into ai-intensive/issue-monitor (default dest)
# Requires ssh/scp available locally and on the remote side.

SERVER_ADDR=${1:-}
DEST_PATH=${2:-ai-intensive/issue-monitor}

if [[ -z "$SERVER_ADDR" ]]; then
  echo "Usage: $0 user@host [dest_path]" >&2
  exit 1
fi

# Locate fat jar
JAR=$(ls -t build/libs/*-all.jar 2>/dev/null | head -n1 || true)
if [[ -z "${JAR}" ]]; then
  echo "Fat JAR not found in build/libs. Build first: ./gradlew :issue-monitor:build" >&2
  exit 2
fi

FILES=(
  "${JAR}"
)

# Optional files
[[ -f README.md ]] && FILES+=("README.md")
[[ -f config.properties ]] && FILES+=("config.properties")

# Create remote dir
ssh "$SERVER_ADDR" "mkdir -p '$DEST_PATH'"

# Copy files
for f in "${FILES[@]}"; do
  echo "Uploading $f -> $SERVER_ADDR:$DEST_PATH/"
  scp -q "$f" "$SERVER_ADDR:$DEST_PATH/"
done

BASENAME=$(basename "$JAR")
echo "Done. Remote path: $SERVER_ADDR:$DEST_PATH"
echo "Tip: ssh $SERVER_ADDR 'cd $DEST_PATH && nohup java -jar $BASENAME > app.log 2>&1 & disown'"
