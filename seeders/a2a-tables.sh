#!/bin/bash

# =============================================================================
# A2A + Calytics Collect – Create DynamoDB tables (LocalStack)
# =============================================================================
# Creates DynamoDB tables in LocalStack:
#   - A2A: payments, idempotency, transaction-codes
#     - PAYMENTS_TABLE_NAME=calytics-a2a-local-payments
#     - TRANSACTION_CODE_TABLE_NAME=calytics-a2a-local-transaction-codes
#   - Calytics Collect: sessions, mandates, audit, webhook-events
# Idempotent: skips creation if a table already exists.
#
# Usage:
#   ./a2a/create-dynamodb-tables.sh
#
# Prerequisite: LocalStack running (e.g. after local-start-infra.sh).
#
# Environment Variables (optional):
#   AWS_ENDPOINT_URL           - LocalStack endpoint (default: http://localhost:4566)
#   AWS_REGION                 - AWS region (default: eu-central-1)
#   PAYMENTS_TABLE_NAME        - Payments table (default: calytics-a2a-local-payments)
#   TRANSACTION_CODE_TABLE_NAME - Transaction codes table (default: calytics-a2a-local-transaction-codes)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"
export AWS_PAGER=""

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'
print_info()    { echo -e "${CYAN}ℹ${NC}  $1"; }
print_success() { echo -e "${GREEN}✓${NC}  $1"; }

ensure_table() {
  local table_name="$1"
  local create_cmd="$2"

  if aws --endpoint-url "$AWS_ENDPOINT_URL" --region "$AWS_REGION" \
      dynamodb describe-table --table-name "$table_name" >/dev/null 2>&1; then
    print_success "DynamoDB table '$table_name' already exists"
  else
    print_info "Creating DynamoDB table '$table_name'..."
    eval "$create_cmd"
    print_success "Created DynamoDB table '$table_name'"
  fi
}

PAYMENTS_TABLE="${PAYMENTS_TABLE_NAME:-${A2A_PAYMENTS_TABLE:-calytics-a2a-local-payments}}"
IDEMPOTENCY_TABLE="${A2A_IDEMPOTENCY_TABLE:-calytics-a2a-local-idempotency}"
TRANSACTION_CODE_TABLE="${TRANSACTION_CODE_TABLE_NAME:-${A2A_TRANSACTION_CODE_TABLE:-calytics-a2a-local-transaction-codes}}"

print_info "Ensuring DynamoDB tables exist for calytics-a2a..."

ensure_table "$PAYMENTS_TABLE" "
aws --endpoint-url $AWS_ENDPOINT_URL --region $AWS_REGION dynamodb create-table \
  --table-name $PAYMENTS_TABLE \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=payment_id,AttributeType=S \
    AttributeName=client_id,AttributeType=S \
    AttributeName=created_at,AttributeType=N \
    AttributeName=tenant_composite_key,AttributeType=S \
    AttributeName=sender_iban,AttributeType=S \
    AttributeName=recipient_iban,AttributeType=S \
    AttributeName=vendor_session_id,AttributeType=S \
  --key-schema AttributeName=payment_id,KeyType=HASH \
  --global-secondary-indexes '[
    {
      \"IndexName\": \"GSI1\",
      \"KeySchema\": [
        {\"AttributeName\": \"client_id\", \"KeyType\": \"HASH\"},
        {\"AttributeName\": \"created_at\", \"KeyType\": \"RANGE\"}
      ],
      \"Projection\": {\"ProjectionType\": \"ALL\"}
    },
    {
      \"IndexName\": \"GSI2\",
      \"KeySchema\": [
        {\"AttributeName\": \"tenant_composite_key\", \"KeyType\": \"HASH\"},
        {\"AttributeName\": \"created_at\", \"KeyType\": \"RANGE\"}
      ],
      \"Projection\": {\"ProjectionType\": \"ALL\"}
    },
    {
      \"IndexName\": \"GSI3\",
      \"KeySchema\": [
        {\"AttributeName\": \"sender_iban\", \"KeyType\": \"HASH\"},
        {\"AttributeName\": \"created_at\", \"KeyType\": \"RANGE\"}
      ],
      \"Projection\": {\"ProjectionType\": \"ALL\"}
    },
    {
      \"IndexName\": \"GSI4\",
      \"KeySchema\": [
        {\"AttributeName\": \"recipient_iban\", \"KeyType\": \"HASH\"},
        {\"AttributeName\": \"created_at\", \"KeyType\": \"RANGE\"}
      ],
      \"Projection\": {\"ProjectionType\": \"ALL\"}
    },
    {
      \"IndexName\": \"GSI5\",
      \"KeySchema\": [
        {\"AttributeName\": \"vendor_session_id\", \"KeyType\": \"HASH\"}
      ],
      \"Projection\": {\"ProjectionType\": \"ALL\"}
    }
  ]'
"

ensure_table "$IDEMPOTENCY_TABLE" "
aws --endpoint-url $AWS_ENDPOINT_URL --region $AWS_REGION dynamodb create-table \
  --table-name $IDEMPOTENCY_TABLE \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions AttributeName=key,AttributeType=S \
  --key-schema AttributeName=key,KeyType=HASH
"

ensure_table "$TRANSACTION_CODE_TABLE" "
aws --endpoint-url $AWS_ENDPOINT_URL --region $AWS_REGION dynamodb create-table \
  --table-name $TRANSACTION_CODE_TABLE \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=PK,AttributeType=S \
    AttributeName=SK,AttributeType=S \
  --key-schema AttributeName=PK,KeyType=HASH AttributeName=SK,KeyType=RANGE
"

# -----------------------------------------------------------------------------
# Calytics Collect tables (stage "local" -> calytics-cc-local-*)
# -----------------------------------------------------------------------------
CC_SESSIONS_TABLE="${CC_SESSIONS_TABLE:-calytics-cc-local-sessions}"
CC_MANDATES_TABLE="${CC_MANDATES_TABLE:-calytics-cc-local-mandates}"
CC_AUDIT_TABLE="${CC_AUDIT_TABLE:-calytics-cc-local-audit-events}"
CC_WEBHOOK_EVENTS_TABLE="${CC_WEBHOOK_EVENTS_TABLE:-calytics-cc-local-webhook-events}"

print_info "Ensuring DynamoDB tables exist for Calytics Collect..."

# Sessions (GSI1, GSI2, GSI3; TTL on ttl)
ensure_table "$CC_SESSIONS_TABLE" "
aws --endpoint-url $AWS_ENDPOINT_URL --region $AWS_REGION dynamodb create-table \
  --table-name $CC_SESSIONS_TABLE \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=session_id,AttributeType=S \
    AttributeName=client_id,AttributeType=S \
    AttributeName=created_at,AttributeType=N \
    AttributeName=vendor_webform_id,AttributeType=S \
    AttributeName=correlation_id,AttributeType=S \
  --key-schema AttributeName=session_id,KeyType=HASH \
  --global-secondary-indexes '[
    {\"IndexName\": \"GSI1\", \"KeySchema\": [{\"AttributeName\": \"client_id\", \"KeyType\": \"HASH\"}, {\"AttributeName\": \"created_at\", \"KeyType\": \"RANGE\"}], \"Projection\": {\"ProjectionType\": \"ALL\"}},
    {\"IndexName\": \"GSI2\", \"KeySchema\": [{\"AttributeName\": \"vendor_webform_id\", \"KeyType\": \"HASH\"}], \"Projection\": {\"ProjectionType\": \"ALL\"}},
    {\"IndexName\": \"GSI3\", \"KeySchema\": [{\"AttributeName\": \"client_id\", \"KeyType\": \"HASH\"}, {\"AttributeName\": \"correlation_id\", \"KeyType\": \"RANGE\"}], \"Projection\": {\"ProjectionType\": \"ALL\"}}
  ]'
"
aws --endpoint-url "$AWS_ENDPOINT_URL" --region "$AWS_REGION" dynamodb update-time-to-live \
  --table-name "$CC_SESSIONS_TABLE" --time-to-live-specification "Enabled=true,AttributeName=ttl" 2>/dev/null || true

# Mandates (GSI1–GSI4)
ensure_table "$CC_MANDATES_TABLE" "
aws --endpoint-url $AWS_ENDPOINT_URL --region $AWS_REGION dynamodb create-table \
  --table-name $CC_MANDATES_TABLE \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=mandate_id,AttributeType=S \
    AttributeName=client_id,AttributeType=S \
    AttributeName=created_at,AttributeType=N \
    AttributeName=correlation_id,AttributeType=S \
    AttributeName=iban_hash,AttributeType=S \
    AttributeName=session_id,AttributeType=S \
  --key-schema AttributeName=mandate_id,KeyType=HASH \
  --global-secondary-indexes '[
    {\"IndexName\": \"GSI1\", \"KeySchema\": [{\"AttributeName\": \"client_id\", \"KeyType\": \"HASH\"}, {\"AttributeName\": \"created_at\", \"KeyType\": \"RANGE\"}], \"Projection\": {\"ProjectionType\": \"ALL\"}},
    {\"IndexName\": \"GSI2\", \"KeySchema\": [{\"AttributeName\": \"client_id\", \"KeyType\": \"HASH\"}, {\"AttributeName\": \"correlation_id\", \"KeyType\": \"RANGE\"}], \"Projection\": {\"ProjectionType\": \"ALL\"}},
    {\"IndexName\": \"GSI3\", \"KeySchema\": [{\"AttributeName\": \"iban_hash\", \"KeyType\": \"HASH\"}], \"Projection\": {\"ProjectionType\": \"ALL\"}},
    {\"IndexName\": \"GSI4\", \"KeySchema\": [{\"AttributeName\": \"session_id\", \"KeyType\": \"HASH\"}], \"Projection\": {\"ProjectionType\": \"ALL\"}}
  ]'
"

# Audit (GSI1-EntityAudit; TTL on ttl)
ensure_table "$CC_AUDIT_TABLE" "
aws --endpoint-url $AWS_ENDPOINT_URL --region $AWS_REGION dynamodb create-table \
  --table-name $CC_AUDIT_TABLE \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=event_id,AttributeType=S \
    AttributeName=entity_key,AttributeType=S \
    AttributeName=created_at,AttributeType=N \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --global-secondary-indexes '[
    {\"IndexName\": \"GSI1-EntityAudit\", \"KeySchema\": [{\"AttributeName\": \"entity_key\", \"KeyType\": \"HASH\"}, {\"AttributeName\": \"created_at\", \"KeyType\": \"RANGE\"}], \"Projection\": {\"ProjectionType\": \"ALL\"}}
  ]'
"
aws --endpoint-url "$AWS_ENDPOINT_URL" --region "$AWS_REGION" dynamodb update-time-to-live \
  --table-name "$CC_AUDIT_TABLE" --time-to-live-specification "Enabled=true,AttributeName=ttl" 2>/dev/null || true

# Webhook events (TTL on ttl)
ensure_table "$CC_WEBHOOK_EVENTS_TABLE" "
aws --endpoint-url $AWS_ENDPOINT_URL --region $AWS_REGION dynamodb create-table \
  --table-name $CC_WEBHOOK_EVENTS_TABLE \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions AttributeName=webhook_id,AttributeType=S \
  --key-schema AttributeName=webhook_id,KeyType=HASH
"
aws --endpoint-url "$AWS_ENDPOINT_URL" --region "$AWS_REGION" dynamodb update-time-to-live \
  --table-name "$CC_WEBHOOK_EVENTS_TABLE" --time-to-live-specification "Enabled=true,AttributeName=ttl" 2>/dev/null || true

print_success "A2A and Calytics Collect DynamoDB tables ready."
