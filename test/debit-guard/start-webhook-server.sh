#!/bin/bash

# Start webhook test server on port 3334
# Usage: ./start-webhook-server.sh [port]
# Stop:  Ctrl+C

PORT=${1:-3334}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="$SCRIPT_DIR/../../../docs/other/testing/webhook-server.js"

if lsof -i:$PORT -t >/dev/null 2>&1; then
    echo "Port $PORT already in use. Kill it first:"
    echo "  kill \$(lsof -t -i:$PORT)"
    exit 1
fi

echo "Webhook URL: http://localhost:$PORT/webhook"
echo "With ngrok:  ngrok http $PORT"
echo ""
node "$SERVER" "$PORT"
