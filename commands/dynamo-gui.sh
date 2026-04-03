#!/bin/bash
# cal dynamo-gui
# Start the DynamoDB admin web UI at http://localhost:8001

CONTAINER_NAME="${CONTAINER_NAME:-dynamodb-gui}"
HOST_PORT="${HOST_PORT:-8001}"
DYNAMO_ENDPOINT="${DYNAMO_ENDPOINT:-http://host.docker.internal:4566}"

phase "Starting DynamoDB Admin GUI"

if container_is_running "$CONTAINER_NAME"; then
  ok "Already running at http://localhost:$HOST_PORT"
  exit 0
fi

docker run -d --rm \
  --name "$CONTAINER_NAME" \
  -p "$HOST_PORT:8001" \
  -e DYNAMO_ENDPOINT="$DYNAMO_ENDPOINT" \
  -e AWS_REGION="$AWS_REGION" \
  -e AWS_ACCESS_KEY_ID=test \
  -e AWS_SECRET_ACCESS_KEY=test \
  aaronshaf/dynamodb-admin 2>/dev/null

ok "DynamoDB Admin GUI running at http://localhost:$HOST_PORT"
