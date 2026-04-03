#!/bin/bash

# =============================================================================
# Seed LocalStack SQS Queues
# =============================================================================
# This script creates all required SQS queues in LocalStack for local
# development of calytics-be and calytics-a2a services.
#
# Usage:
#   ./seed-localstack-queues.sh
#
# Environment Variables (optional - defaults provided):
#   AWS_ENDPOINT_URL        - LocalStack endpoint (default: http://localhost:4566)
#   AWS_REGION              - AWS region (default: eu-central-1)
#   SERVICE_NAME            - Service name prefix (default: calytics-be)
#   STAGE                   - Environment stage (default: local)
#   DATA_ENRICHMENT_QUEUE   - Data enrichment queue name (auto-generated if not set)
#   CLIENT_CALLBACK_QUEUE   - Client callback queue name (auto-generated if not set)
#   CLIENT_CALLBACK_DLQ     - Client callback DLQ name (auto-generated if not set)
#   SEED_A2A_QUEUES         - If 1, also create calytics-a2a data-enrichment queues (default: 1)
#   A2A_DATA_ENRICHMENT_QUEUE - A2A data-enrichment queue name (default: calytics-a2a-local-data-enrichment.fifo)
#   A2A_DATA_ENRICHMENT_DLQ   - A2A data-enrichment DLQ name (default: calytics-a2a-local-data-enrichment-dlq.fifo)
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
SERVICE_NAME="${SERVICE_NAME:-calytics-be}"
STAGE="${STAGE:-local}"

# Queue Names (can be overridden via environment variables)
DATA_ENRICHMENT_QUEUE="${DATA_ENRICHMENT_QUEUE:-${SERVICE_NAME}-${STAGE}-data-enrichment.fifo}"
DATA_ENRICHMENT_DLQ="${DATA_ENRICHMENT_DLQ:-${SERVICE_NAME}-${STAGE}-data-enrichment-dlq.fifo}"
CLIENT_CALLBACK_QUEUE="${CLIENT_CALLBACK_QUEUE:-${SERVICE_NAME}-${STAGE}-client-callback}"
CLIENT_CALLBACK_DLQ="${CLIENT_CALLBACK_DLQ:-${SERVICE_NAME}-${STAGE}-client-callback-dlq}"

# Calytics-A2A (data-enrichment only - used by calytics-a2a serverless offline)
# Set SEED_A2A_QUEUES=1 to also create these when seeding for calytics-be
A2A_DATA_ENRICHMENT_QUEUE="${A2A_DATA_ENRICHMENT_QUEUE:-calytics-a2a-local-data-enrichment.fifo}"
A2A_DATA_ENRICHMENT_DLQ="${A2A_DATA_ENRICHMENT_DLQ:-calytics-a2a-local-data-enrichment-dlq.fifo}"
SEED_A2A_QUEUES="${SEED_A2A_QUEUES:-1}"

# Queue Settings
MESSAGE_RETENTION_PERIOD="${MESSAGE_RETENTION_PERIOD:-1209600}"  # 14 days
VISIBILITY_TIMEOUT="${VISIBILITY_TIMEOUT:-70}"
MAX_RECEIVE_COUNT="${MAX_RECEIVE_COUNT:-4}"

# =============================================================================
# Colors and Formatting
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

print_header() {
    echo -e "\n${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_info() {
    echo -e "${CYAN}ℹ${NC}  $1"
}

print_success() {
    echo -e "${GREEN}✓${NC}  $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

print_error() {
    echo -e "${RED}✗${NC}  $1"
}

# =============================================================================
# Helper Functions
# =============================================================================

# Create a queue if it doesn't exist
create_queue() {
    local queue_name="$1"
    local is_fifo="${2:-false}"
    local attributes="${3:-}"
    
    print_info "Checking queue: ${BOLD}$queue_name${NC}"
    
    # Check if queue exists
    if aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
        sqs get-queue-url --queue-name "$queue_name" &>/dev/null; then
        print_warn "Queue already exists: $queue_name"
        return 0
    fi
    
    print_info "Creating queue: $queue_name"
    
    if [ "$is_fifo" = "true" ]; then
        aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
            sqs create-queue \
            --queue-name "$queue_name" \
            --attributes "FifoQueue=true,ContentBasedDeduplication=true${attributes:+,$attributes}" \
            > /dev/null
    else
        if [ -n "$attributes" ]; then
            aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
                sqs create-queue \
                --queue-name "$queue_name" \
                --attributes "$attributes" \
                > /dev/null
        else
            aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
                sqs create-queue \
                --queue-name "$queue_name" \
                > /dev/null
        fi
    fi
    
    print_success "Created: $queue_name"
}

# Get queue URL
get_queue_url() {
    local queue_name="$1"
    aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
        sqs get-queue-url \
        --queue-name "$queue_name" \
        --query 'QueueUrl' \
        --output text
}

# Get queue ARN
get_queue_arn() {
    local queue_url="$1"
    aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
        sqs get-queue-attributes \
        --queue-url "$queue_url" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' \
        --output text
}

# =============================================================================
# Main Script
# =============================================================================

print_header "📬 Seeding LocalStack SQS Queues"

echo -e "Configuration:"
echo -e "  Endpoint:     ${CYAN}$AWS_ENDPOINT_URL${NC}"
echo -e "  Region:       ${CYAN}$AWS_REGION${NC}"
echo -e "  Service:      ${CYAN}$SERVICE_NAME${NC}"
echo -e "  Stage:        ${CYAN}$STAGE${NC}"
echo ""
echo -e "Queue Names:"
echo -e "  Data Enrichment:       ${CYAN}$DATA_ENRICHMENT_QUEUE${NC}"
echo -e "  Data Enrichment DLQ:   ${CYAN}$DATA_ENRICHMENT_DLQ${NC}"
echo -e "  Client Callback:       ${CYAN}$CLIENT_CALLBACK_QUEUE${NC}"
echo -e "  Client Callback DLQ:   ${CYAN}$CLIENT_CALLBACK_DLQ${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Create Dead Letter Queues
# -----------------------------------------------------------------------------
print_header "Step 1: Creating Dead Letter Queues"

# Data Enrichment DLQ (FIFO - must match main queue type)
create_queue \
    "$DATA_ENRICHMENT_DLQ" \
    "true" \
    "MessageRetentionPeriod=$MESSAGE_RETENTION_PERIOD"

# Client Callback DLQ (Standard)
create_queue \
    "$CLIENT_CALLBACK_DLQ" \
    "false" \
    "MessageRetentionPeriod=$MESSAGE_RETENTION_PERIOD"

# -----------------------------------------------------------------------------
# Step 2: Create Main Queues
# -----------------------------------------------------------------------------
print_header "Step 2: Creating Main Queues"

# Data Enrichment Queue (FIFO)
create_queue \
    "$DATA_ENRICHMENT_QUEUE" \
    "true" \
    ""

# Client Callbacks Queue (Standard)
create_queue \
    "$CLIENT_CALLBACK_QUEUE" \
    "false" \
    "MessageRetentionPeriod=$MESSAGE_RETENTION_PERIOD,VisibilityTimeout=$VISIBILITY_TIMEOUT"

# -----------------------------------------------------------------------------
# Step 3: Configure Redrive Policies
# -----------------------------------------------------------------------------
print_header "Step 3: Configuring Redrive Policies"

# --- Data Enrichment Queue Redrive Policy ---
print_info "Configuring redrive policy for Data Enrichment queue..."

# Get Data Enrichment DLQ URL and ARN
DATA_ENRICHMENT_DLQ_URL=$(get_queue_url "$DATA_ENRICHMENT_DLQ")
DATA_ENRICHMENT_DLQ_ARN=$(get_queue_arn "$DATA_ENRICHMENT_DLQ_URL")

print_info "Data Enrichment DLQ ARN: $DATA_ENRICHMENT_DLQ_ARN"

# Get Data Enrichment queue URL
DATA_ENRICHMENT_URL=$(get_queue_url "$DATA_ENRICHMENT_QUEUE")

# Set RedrivePolicy on Data Enrichment queue
aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
    sqs set-queue-attributes \
    --queue-url "$DATA_ENRICHMENT_URL" \
    --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DATA_ENRICHMENT_DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"$MAX_RECEIVE_COUNT\\\"}\"}" \
    > /dev/null

print_success "Redrive policy configured for $DATA_ENRICHMENT_QUEUE"

# --- Client Callback Queue Redrive Policy ---
print_info "Configuring redrive policy for Client Callback queue..."

# Get Client Callback DLQ URL and ARN
CLIENT_CALLBACK_DLQ_URL=$(get_queue_url "$CLIENT_CALLBACK_DLQ")
CLIENT_CALLBACK_DLQ_ARN=$(get_queue_arn "$CLIENT_CALLBACK_DLQ_URL")

print_info "Client Callback DLQ ARN: $CLIENT_CALLBACK_DLQ_ARN"

# Get Client Callback queue URL
CLIENT_CALLBACK_URL=$(get_queue_url "$CLIENT_CALLBACK_QUEUE")

# Set RedrivePolicy on Client Callback queue
aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
    sqs set-queue-attributes \
    --queue-url "$CLIENT_CALLBACK_URL" \
    --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$CLIENT_CALLBACK_DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"$MAX_RECEIVE_COUNT\\\"}\"}" \
    > /dev/null

print_success "Redrive policy configured for $CLIENT_CALLBACK_QUEUE"

# -----------------------------------------------------------------------------
# Step 4: Calytics-A2A data-enrichment queues (for calytics-a2a serverless offline)
# -----------------------------------------------------------------------------
if [ "${SEED_A2A_QUEUES}" = "1" ]; then
  print_header "Step 4: Calytics-A2A data-enrichment queues"

  # A2A Data Enrichment DLQ (FIFO)
  create_queue \
    "$A2A_DATA_ENRICHMENT_DLQ" \
    "true" \
    "MessageRetentionPeriod=$MESSAGE_RETENTION_PERIOD"

  # A2A Data Enrichment Queue (FIFO)
  create_queue \
    "$A2A_DATA_ENRICHMENT_QUEUE" \
    "true" \
    ""

  # Redrive policy for A2A data-enrichment queue
  if aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
      sqs get-queue-url --queue-name "$A2A_DATA_ENRICHMENT_QUEUE" &>/dev/null; then
    A2A_DLQ_URL=$(get_queue_url "$A2A_DATA_ENRICHMENT_DLQ")
    A2A_DLQ_ARN=$(get_queue_arn "$A2A_DLQ_URL")
    A2A_QUEUE_URL=$(get_queue_url "$A2A_DATA_ENRICHMENT_QUEUE")
    aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
      sqs set-queue-attributes \
      --queue-url "$A2A_QUEUE_URL" \
      --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$A2A_DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}" \
      > /dev/null
    print_success "Redrive policy configured for $A2A_DATA_ENRICHMENT_QUEUE"
  fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "📋 Summary"

echo -e "All queues have been created in LocalStack."
echo ""
echo -e "Queue URLs (for .env file):"
echo -e "  ${BOLD}DATA_ENRICHMENT_QUEUE_URL${NC}=${CYAN}$DATA_ENRICHMENT_URL${NC}"
echo -e "  ${BOLD}CLIENT_CALLBACKS_QUEUE_URL${NC}=${CYAN}$CLIENT_CALLBACK_URL${NC}"
if [ "${SEED_A2A_QUEUES}" = "1" ] && aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" sqs get-queue-url --queue-name "$A2A_DATA_ENRICHMENT_QUEUE" &>/dev/null; then
  A2A_DE_URL=$(get_queue_url "$A2A_DATA_ENRICHMENT_QUEUE")
  echo -e "  ${BOLD}DATA_ENRICHMENT_QUEUE_URL (calytics-a2a)${NC}=${CYAN}$A2A_DE_URL${NC}"
fi
echo ""
echo -e "Dead Letter Queue URLs:"
echo -e "  ${BOLD}DATA_ENRICHMENT_DLQ_URL${NC}=${CYAN}$DATA_ENRICHMENT_DLQ_URL${NC}"
echo -e "  ${BOLD}CLIENT_CALLBACK_DLQ_URL${NC}=${CYAN}$CLIENT_CALLBACK_DLQ_URL${NC}"

echo ""
echo -e "Available queues:"
aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
    sqs list-queues \
    --output json 2>/dev/null | jq -r '.QueueUrls[]' 2>/dev/null | sed 's/^/  - /' || echo "  (none)"

echo ""
print_success "LocalStack SQS queues seeding completed!"
