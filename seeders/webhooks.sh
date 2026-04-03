#!/bin/bash

# Seeder script for webhooks and API settings
# This script deletes then recreates all webhooks and API settings for the client
# (main.client@gmail.com). No duplicates: every run replaces existing data.

set -euo pipefail

# Configuration
CLIENT_EMAIL="main.client@gmail.com"
AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-register}"
POSTGRES_DB="${POSTGRES_DB:-calytics-admin}"

# Disable pagers so psql and aws never open less/vim
export PAGER=cat
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper function to print colored messages
print_info() {
    echo -e "${GREEN}ℹ${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Helper function to execute PostgreSQL queries
psql_exec() {
    PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        -t -A \
        -c "$1"
}

# Helper function to execute PostgreSQL queries with output
psql_query() {
    PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        -c "$1"
}

# Step 1: Get client ID by email
print_info "Step 1: Getting client ID for email: $CLIENT_EMAIL"
CLIENT_ID=$(psql_exec "SELECT id FROM clients WHERE email = '$CLIENT_EMAIL';")

if [ -z "$CLIENT_ID" ]; then
    print_error "Client with email $CLIENT_EMAIL not found!"
    exit 1
fi

print_success "Found client ID: $CLIENT_ID"

# Step 2: Delete existing webhooks and API settings for this client (then recreate below)
print_info "Step 2: Deleting existing webhooks and API settings for client ID: $CLIENT_ID"

# Get all webhook IDs for this client (via client_api_settings) to delete their secrets
WEBHOOK_IDS=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -q -c \
    "SELECT cw.id FROM client_webhooks cw JOIN client_api_settings cas ON cw.client_api_settings_id = cas.id WHERE cas.client_id = '$CLIENT_ID';" 2>/dev/null) || true
if [ -n "$WEBHOOK_IDS" ]; then
    for webhook_id in $WEBHOOK_IDS; do
        [ -z "$webhook_id" ] && continue
        SECRET_NAME="clients/$CLIENT_ID/webhooks/$webhook_id"
        aws --endpoint-url="$AWS_ENDPOINT_URL" \
            secretsmanager delete-secret \
            --secret-id "$SECRET_NAME" \
            --force-delete-without-recovery \
            2>/dev/null || true
    done
fi
# Delete webhooks then API settings (FK: webhooks reference api_settings)
psql_exec "DELETE FROM client_webhooks WHERE client_api_settings_id IN (SELECT id FROM client_api_settings WHERE client_id = '$CLIENT_ID');" > /dev/null
psql_exec "DELETE FROM client_api_settings WHERE client_id = '$CLIENT_ID';" > /dev/null
print_success "Deleted existing webhooks and API settings"

# Step 3: Create API settings
print_info "Step 3: Creating API settings"
psql_exec "
    INSERT INTO client_api_settings (id, ip_allow_list, white_list_parameters, api_base_url, client_id)
    VALUES (
        gen_random_uuid(),
        ARRAY['127.0.0.1'],
        ARRAY[]::text[],
        'https://api.calytics.io',
        '$CLIENT_ID'
    );
" > /dev/null
API_SETTINGS_ID=$(psql_exec "SELECT id FROM client_api_settings WHERE client_id = '$CLIENT_ID';")
print_success "Created API settings with ID: $API_SETTINGS_ID"

# Step 4 & 5: Create webhooks and secrets
print_info "Step 4 & 5: Creating webhooks and secrets"

# Webhook 1: Local - A2A & CC (A2A + CalyticsCollect events)
WEBHOOK_1_ID="5e11e707-a3f1-4799-a356-27727fb5aade"
WEBHOOK_1_LABEL="Local - A2A & CC"
WEBHOOK_1_CALLBACK_URL="https://webhook-test.com/4aba0f16c738ea2f882f3da77c3d9d3e"
WEBHOOK_1_SIGNING_SECRET="6b2935e5f69390f9064f3f975a2a21ddd3a823b0a213a03a25d909812acc405b"
# Events: A2APaymentFinalized, CalyticsCollect SessionAccountsReady/SessionFailed, MandateCreated/MandateDeactivated (backend dotted format)
WEBHOOK_1_EVENTS=(
  "a2a.payment.finalized"
  "calytics_collect.session.accounts_ready"
  "calytics_collect.session.failed"
  "calytics_collect.mandate.created"
  "calytics_collect.mandate.deactivated"
)
WEBHOOK_1_SECRET_VALUE="a28d6b30e8eb87864013cd9e15098536b77cef8db4e654087b5fd08c3ff2e661"

print_info "Creating webhook 1: $WEBHOOK_1_LABEL"
SECRET_NAME_1="clients/$CLIENT_ID/webhooks/$WEBHOOK_1_ID"

# Create secret in AWS Secrets Manager (create or update)
if aws --endpoint-url="$AWS_ENDPOINT_URL" \
    secretsmanager describe-secret \
    --secret-id "$SECRET_NAME_1" \
    >/dev/null 2>&1; then
    # Secret exists, update it
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME_1" \
        --secret-string "$WEBHOOK_1_SECRET_VALUE" \
        > /dev/null
else
    # Secret doesn't exist, create it
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager create-secret \
        --name "$SECRET_NAME_1" \
        --secret-string "$WEBHOOK_1_SECRET_VALUE" \
        > /dev/null
fi

# Build ARRAY['ev1','ev2',...] for webhook 1 events
WEBHOOK_1_EVENTS_SQL="ARRAY[$(printf "'%s'," "${WEBHOOK_1_EVENTS[@]}" | sed "s/,$//")]"

# Create webhook in database
psql_exec "
    INSERT INTO client_webhooks (id, label, callback_url, encrypted_signing_secret, events, client_api_settings_id)
    VALUES (
        '$WEBHOOK_1_ID',
        '$WEBHOOK_1_LABEL',
        '$WEBHOOK_1_CALLBACK_URL',
        '$WEBHOOK_1_SIGNING_SECRET',
        $WEBHOOK_1_EVENTS_SQL,
        '$API_SETTINGS_ID'
    );
" > /dev/null

print_success "Created webhook 1: $WEBHOOK_1_LABEL (ID: $WEBHOOK_1_ID)"

# Webhook 2: Local - DG
WEBHOOK_2_ID="b5b021a7-1158-46e3-b1a7-efdf631d8acf"
WEBHOOK_2_LABEL="Local - DG"
WEBHOOK_2_CALLBACK_URL="https://webhook-test.com/17438064aebe3fc88fdd2905eb5fb0fd"
WEBHOOK_2_SIGNING_SECRET="63ae00862273a7d993632621d7b320aad61d753d0ec51940a454c4a87dded9d3"
WEBHOOK_2_EVENTS="debit_guard.verification_completed"
WEBHOOK_2_SECRET_VALUE="24ed3398a46196e78d1818b77ee0a4dd512ef44ba6236a75e094154c89d5907e"

print_info "Creating webhook 2: $WEBHOOK_2_LABEL"
SECRET_NAME_2="clients/$CLIENT_ID/webhooks/$WEBHOOK_2_ID"

# Create secret in AWS Secrets Manager (create or update)
if aws --endpoint-url="$AWS_ENDPOINT_URL" \
    secretsmanager describe-secret \
    --secret-id "$SECRET_NAME_2" \
    >/dev/null 2>&1; then
    # Secret exists, update it
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME_2" \
        --secret-string "$WEBHOOK_2_SECRET_VALUE" \
        > /dev/null
else
    # Secret doesn't exist, create it
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager create-secret \
        --name "$SECRET_NAME_2" \
        --secret-string "$WEBHOOK_2_SECRET_VALUE" \
        > /dev/null
fi

# Create webhook in database
psql_exec "
    INSERT INTO client_webhooks (id, label, callback_url, encrypted_signing_secret, events, client_api_settings_id)
    VALUES (
        '$WEBHOOK_2_ID',
        '$WEBHOOK_2_LABEL',
        '$WEBHOOK_2_CALLBACK_URL',
        '$WEBHOOK_2_SIGNING_SECRET',
        ARRAY['$WEBHOOK_2_EVENTS'],
        '$API_SETTINGS_ID'
    );
" > /dev/null

print_success "Created webhook 2: $WEBHOOK_2_LABEL (ID: $WEBHOOK_2_ID)"

# Webhook 3: Local - OC
WEBHOOK_3_ID="4b36cba2-d575-4b69-b185-01d1fd8aacbf"
WEBHOOK_3_LABEL="Local - OC"
WEBHOOK_3_CALLBACK_URL="https://webhook-test.com/6767f568bcbe01826d527de522d24e2b"
WEBHOOK_3_SIGNING_SECRET="ed33c2d722b8163ea353441b8d4fe2ebed65e158828d26dd66a351e646612711"
WEBHOOK_3_EVENTS="ownership_check.verification_completed"
WEBHOOK_3_SECRET_VALUE="05d3d93b00fb992b5ada893e345b5b6971a8fe908dff70020d3c255a5d91a6d4"

print_info "Creating webhook 3: $WEBHOOK_3_LABEL"
SECRET_NAME_3="clients/$CLIENT_ID/webhooks/$WEBHOOK_3_ID"

# Create secret in AWS Secrets Manager (create or update)
if aws --endpoint-url="$AWS_ENDPOINT_URL" \
    secretsmanager describe-secret \
    --secret-id "$SECRET_NAME_3" \
    >/dev/null 2>&1; then
    # Secret exists, update it
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME_3" \
        --secret-string "$WEBHOOK_3_SECRET_VALUE" \
        > /dev/null
else
    # Secret doesn't exist, create it
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager create-secret \
        --name "$SECRET_NAME_3" \
        --secret-string "$WEBHOOK_3_SECRET_VALUE" \
        > /dev/null
fi

# Create webhook in database
psql_exec "
    INSERT INTO client_webhooks (id, label, callback_url, encrypted_signing_secret, events, client_api_settings_id)
    VALUES (
        '$WEBHOOK_3_ID',
        '$WEBHOOK_3_LABEL',
        '$WEBHOOK_3_CALLBACK_URL',
        '$WEBHOOK_3_SIGNING_SECRET',
        ARRAY['$WEBHOOK_3_EVENTS'],
        '$API_SETTINGS_ID'
    );
" > /dev/null

print_success "Created webhook 3: $WEBHOOK_3_LABEL (ID: $WEBHOOK_3_ID)"

# Verification: Display final state
print_info "Verification: Final state"
echo ""
echo "Client API Settings:"
psql_query "SELECT id, ip_allow_list, white_list_parameters, api_base_url, client_id FROM client_api_settings WHERE client_id = '$CLIENT_ID';"
echo ""
echo "Webhooks:"
psql_query "SELECT id, label, callback_url, events FROM client_webhooks WHERE client_api_settings_id = '$API_SETTINGS_ID' ORDER BY label;"
echo ""
echo "Secrets in AWS Secrets Manager:"
aws --endpoint-url="$AWS_ENDPOINT_URL" \
    secretsmanager list-secrets \
    --query "SecretList[?starts_with(Name, 'clients/$CLIENT_ID/webhooks/')].{Name:Name, ARN:ARN}" \
    --output table

print_success "Seeder completed successfully! All webhooks and API settings have been deleted and recreated."

