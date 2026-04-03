#!/bin/bash
# Sync vendor credentials from AWS to LocalStack
# Usage: bash sync-secrets.sh <finapi|qonto>

target="${1:-}"
AWS_REGION="eu-central-1"
LOCALSTACK_ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"

sync_secret() {
  local from_id="$1" to_id="$2" from_region="${3:-$AWS_REGION}"
  local value
  value=$(aws secretsmanager get-secret-value --secret-id "$from_id" --region "$from_region" --query SecretString --output text 2>/dev/null) || { echo "  WARN: Could not fetch $from_id"; return 1; }
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" secretsmanager delete-secret --secret-id "$to_id" --force-delete-without-recovery --region "$AWS_REGION" 2>/dev/null || true
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" secretsmanager create-secret --name "$to_id" --secret-string "$value" --region "$AWS_REGION" 2>/dev/null
  echo "  OK: $to_id"
}

case "$target" in
  finapi)
    echo "Syncing FinAPI sandbox → local..."
    sync_secret "calytics/calytics-be/sandbox/finapi/credentials" "calytics/calytics-be/local/finapi/credentials"
    sync_secret "calytics/calytics-be/sandbox/finapi/static-credentials" "calytics/calytics-be/local/finapi/static-credentials"
    ;;
  qonto)
    echo "Syncing Qonto production → local..."
    sync_secret "calytics/calytics-be/production/qonto/credentials" "calytics/qonto/credentials"
    sync_secret "calytics/calytics-be/production/qonto/static-credentials" "calytics/qonto/static-credentials"
    ;;
  *) echo "Usage: $0 <finapi|qonto>"; exit 1 ;;
esac
