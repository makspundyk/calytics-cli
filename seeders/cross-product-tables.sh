#!/bin/bash

# =============================================================================
# Calytics-Cross-Product DynamoDB tables (LocalStack)
# =============================================================================
# Creates the cross-product tables that production provisions via Terraform
# in an external infra repo:
#   - cross-product-local-worker-tasks (deferred worker tasks for matcher)
#   - cross-product-local-returns-log  (DEC-020 SEPA returns audit log)
#
# Idempotent: skips creation if a table already exists.
#
# Usage:
#   bash seeders/cross-product-tables.sh
#
# Environment Variables (optional):
#   AWS_ENDPOINT_URL                   - LocalStack endpoint (default http://localhost:4566)
#   AWS_REGION                         - AWS region (default eu-central-1)
#   CROSS_PRODUCT_WORKER_TASKS_TABLE   - Worker tasks table (default cross-product-local-worker-tasks)
#   CROSS_PRODUCT_RETURNS_LOG_TABLE    - Returns log table (default cross-product-local-returns-log)
# =============================================================================

set -euo pipefail

export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"
export AWS_PAGER=""

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

WORKER_TASKS_TABLE="${CROSS_PRODUCT_WORKER_TASKS_TABLE:-cross-product-local-worker-tasks}"
RETURNS_LOG_TABLE="${CROSS_PRODUCT_RETURNS_LOG_TABLE:-cross-product-local-returns-log}"

print_info "Ensuring DynamoDB tables exist for calytics-cross-product..."

# Worker tasks: PK/SK + GSI1 (status-availability index for the claim queue).
# Mirrors src/infrastructure/worker/repositories/WorkerTaskDynamoRepository toItem() shape.
ensure_table "$WORKER_TASKS_TABLE" "
aws --endpoint-url $AWS_ENDPOINT_URL --region $AWS_REGION dynamodb create-table \
  --table-name $WORKER_TASKS_TABLE \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=PK,AttributeType=S \
    AttributeName=SK,AttributeType=S \
    AttributeName=GSI1PK,AttributeType=S \
    AttributeName=GSI1SK,AttributeType=S \
  --key-schema \
    AttributeName=PK,KeyType=HASH \
    AttributeName=SK,KeyType=RANGE \
  --global-secondary-indexes '[
    {\"IndexName\": \"GSI1\", \"KeySchema\": [{\"AttributeName\": \"GSI1PK\", \"KeyType\": \"HASH\"}, {\"AttributeName\": \"GSI1SK\", \"KeyType\": \"RANGE\"}], \"Projection\": {\"ProjectionType\": \"ALL\"}}
  ]'
"

# Returns log (DEC-020): PK = RETURN#client#tenant, SK = BANKTX#id.
# Append-only audit; idempotency enforced via attribute_not_exists(PK) on the put.
ensure_table "$RETURNS_LOG_TABLE" "
aws --endpoint-url $AWS_ENDPOINT_URL --region $AWS_REGION dynamodb create-table \
  --table-name $RETURNS_LOG_TABLE \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions \
    AttributeName=PK,AttributeType=S \
    AttributeName=SK,AttributeType=S \
  --key-schema \
    AttributeName=PK,KeyType=HASH \
    AttributeName=SK,KeyType=RANGE
"

print_success "Cross-product DynamoDB tables ready."
