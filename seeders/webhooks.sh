#!/bin/bash

# Seeder script for webhooks and API settings
# This script deletes then recreates all webhooks and API settings for the client
# (main.client@gmail.com). No duplicates: every run replaces existing data.
#
# Webhook callback URLs use FIXED session UUIDs (from lib/names.sh) pointing at
# the local webhook-tester container. The container runs with
# --auto-create-sessions, so this seeder only sends a HEAD ping per UUID to
# materialize the session if it's missing on a fresh data volume.

set -euo pipefail

# Configuration
CLIENT_EMAIL="${CRED_CLIENT_EMAIL:-main.client@gmail.com}"
# Host-side base URL — used by this seeder to ping/verify webhook-tester
# from the host (via :8090 host port) and to print human-friendly inspector URLs.
WEBHOOK_API="${WEBHOOK_BASE_URL:-http://localhost:8090}"
# Container-side base URL — what we persist into PG `client_webhooks.callback_url`.
# be-admin runs in Docker and reaches webhook-tester via container DNS on its
# internal port (8080), not via the host-mapped 8090. Default mirrors the value
# exported by lib/names.sh ($WEBHOOK_INTERNAL_BASE_URL).
WEBHOOK_INTERNAL_API="${WEBHOOK_INTERNAL_BASE_URL:-http://calytics-webhook-tester:8080}"
AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-register}"
POSTGRES_DB="${POSTGRES_DB:-calytics-admin}"

# Pinned per-product session UUIDs (mirrored from lib/names.sh; defaults here
# keep the seeder runnable even if invoked outside the cal harness).
WH_DG_UUID="${WEBHOOK_SESSION_DG:-a0937803-8760-4282-83ce-873ca2d1d78c}"
WH_OC_UUID="${WEBHOOK_SESSION_OC:-844af3bb-3fda-45df-a823-d4ef235309dc}"
WH_A2A_UUID="${WEBHOOK_SESSION_A2A:-f5e27a02-ad19-4641-8e56-8bc9f4d33cfb}"

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

# Master AES key value for `webhook` issuer. Must match the secret seeded by
# seeders/secrets.sh under name `calytics-be-admin/webhook-encryption`.
# be-admin's CryptoService takes SHA-256 of this string as the AES-256-GCM key.
WEBHOOK_MASTER_PLAINTEXT="${WEBHOOK_MASTER_PLAINTEXT:-local-dev-webhook-encryption-secret-32chars!}"

# Encrypt a plaintext signing secret with the same AES-256-GCM scheme that
# calytics-be-admin's CryptoOrchestratorRepository uses, so the consumer can
# decrypt the ciphertext stored in `client_webhooks.encrypted_signing_secret`.
#
# Format: base64( iv[12] || authTag[16] || ciphertext )
# Key:    sha256(WEBHOOK_MASTER_PLAINTEXT)
encrypt_webhook_secret() {
    local plain="$1"
    node -e '
        const crypto = require("crypto");
        const master = process.argv[1];
        const plain  = process.argv[2];
        const key = crypto.createHash("sha256").update(master, "utf8").digest();
        const iv  = crypto.randomBytes(12);
        const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
        const ct  = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
        const tag = cipher.getAuthTag();
        process.stdout.write(Buffer.concat([iv, tag, ct]).toString("base64"));
    ' "$WEBHOOK_MASTER_PLAINTEXT" "$plain"
}

# Step 1: Get client ID by email
print_info "Step 1: Getting client ID for email: $CLIENT_EMAIL"
# CPM refactor (Jun 2026): client login identity moved out of `clients` into the
# `users` table. `clients.email` was dropped; the login email now lives on the
# CLIENTS_ADMIN user, linked to its client via the `user_clients` join table.
CLIENT_ID=$(psql_exec "SELECT uc.client_id FROM user_clients uc JOIN users u ON u.user_id = uc.user_id WHERE u.email = '$CLIENT_EMAIL' LIMIT 1;")

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

# Step 4: Ensure webhook-tester sessions exist for the pinned UUIDs.
# webhook-tester v2 doesn't accept a custom UUID via /api/session; instead, with
# --auto-create-sessions enabled, any inbound request to /{uuid} materializes
# the session. A single HEAD ping is enough.
print_info "Step 4: Ensuring webhook-tester sessions exist"

ensure_webhook_session() {
    label="$1"
    uuid="$2"
    callback="$WEBHOOK_API/$uuid"
    inspector="$WEBHOOK_API/s/$uuid"
    if curl -sf -o /dev/null "$WEBHOOK_API/api/session/$uuid" 2>/dev/null; then
        print_success "  $label (existing)"
    elif curl -sIf -o /dev/null "$WEBHOOK_API/$uuid" 2>/dev/null \
         && curl -sf -o /dev/null "$WEBHOOK_API/api/session/$uuid" 2>/dev/null; then
        print_success "  $label (created)"
    else
        print_warn "  $label - webhook-tester not reachable; URL still seeded"
    fi
    echo "      callback:  $callback"
    echo "      inspector: $inspector"
}

ensure_webhook_session "DebitGuard"     "$WH_DG_UUID"
ensure_webhook_session "OwnershipCheck" "$WH_OC_UUID"
ensure_webhook_session "A2A + CC"       "$WH_A2A_UUID"

# Build callback URLs from fixed UUIDs
# Callback URLs persisted in PG must use the container-side base; be-admin
# resolves them at delivery time from inside the docker network.
WH_CALLBACK_DG="$WEBHOOK_INTERNAL_API/$WH_DG_UUID"
WH_CALLBACK_OC="$WEBHOOK_INTERNAL_API/$WH_OC_UUID"
WH_CALLBACK_A2A="$WEBHOOK_INTERNAL_API/$WH_A2A_UUID"

# Step 5 & 6: Create webhooks and secrets
print_info "Step 5 & 6: Creating webhooks and secrets"

# Webhook 1: Local - A2A & CC (A2A + SmartDebit events)
WEBHOOK_1_ID="5e11e707-a3f1-4799-a356-27727fb5aade"
WEBHOOK_1_LABEL="Local - A2A & CC"
WEBHOOK_1_CALLBACK_URL="$WH_CALLBACK_A2A"
# Single source of truth: this plaintext is stored as-is in Secrets Manager
# AND encrypted with the webhook master key for the PostgreSQL row, so the
# consumer's HMAC and the support-revealable secret stay in sync.
WEBHOOK_1_PLAIN_SIGNING_SECRET="6b2935e5f69390f9064f3f975a2a21ddd3a823b0a213a03a25d909812acc405b"
# Events: A2APaymentFinalized, SmartDebit SessionAccountsReady/SessionFailed, MandateCreated/MandateDeactivated (backend dotted format)
WEBHOOK_1_EVENTS=(
  "a2a.payment.finalized"
  "smart_debit.session.accounts_ready"
  "smart_debit.session.failed"
  "smart_debit.mandate.created"
  "smart_debit.mandate.deactivated"
)

print_info "Creating webhook 1: $WEBHOOK_1_LABEL"
SECRET_NAME_1="clients/$CLIENT_ID/webhooks/$WEBHOOK_1_ID"

# Create secret in AWS Secrets Manager (create or update)
if aws --endpoint-url="$AWS_ENDPOINT_URL" \
    secretsmanager describe-secret \
    --secret-id "$SECRET_NAME_1" \
    >/dev/null 2>&1; then
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME_1" \
        --secret-string "$WEBHOOK_1_PLAIN_SIGNING_SECRET" \
        > /dev/null
else
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager create-secret \
        --name "$SECRET_NAME_1" \
        --secret-string "$WEBHOOK_1_PLAIN_SIGNING_SECRET" \
        > /dev/null
fi

WEBHOOK_1_ENCRYPTED_SECRET=$(encrypt_webhook_secret "$WEBHOOK_1_PLAIN_SIGNING_SECRET")

# Build ARRAY['ev1','ev2',...] for webhook 1 events
WEBHOOK_1_EVENTS_SQL="ARRAY[$(printf "'%s'," "${WEBHOOK_1_EVENTS[@]}" | sed "s/,$//")]"

# Create webhook in database — encrypted_signing_secret holds AES-256-GCM
# ciphertext (base64) so be-admin's CryptoService.decrypt('webhook') succeeds.
psql_exec "
    INSERT INTO client_webhooks (id, label, callback_url, encrypted_signing_secret, events, client_api_settings_id)
    VALUES (
        '$WEBHOOK_1_ID',
        '$WEBHOOK_1_LABEL',
        '$WEBHOOK_1_CALLBACK_URL',
        '$WEBHOOK_1_ENCRYPTED_SECRET',
        $WEBHOOK_1_EVENTS_SQL,
        '$API_SETTINGS_ID'
    );
" > /dev/null

print_success "Created webhook 1: $WEBHOOK_1_LABEL (ID: $WEBHOOK_1_ID)"

# Webhook 2: Local - DG
WEBHOOK_2_ID="b5b021a7-1158-46e3-b1a7-efdf631d8acf"
WEBHOOK_2_LABEL="Local - DG"
WEBHOOK_2_CALLBACK_URL="$WH_CALLBACK_DG"
WEBHOOK_2_PLAIN_SIGNING_SECRET="63ae00862273a7d993632621d7b320aad61d753d0ec51940a454c4a87dded9d3"
WEBHOOK_2_EVENTS="debit_guard.verification_completed"

print_info "Creating webhook 2: $WEBHOOK_2_LABEL"
SECRET_NAME_2="clients/$CLIENT_ID/webhooks/$WEBHOOK_2_ID"

if aws --endpoint-url="$AWS_ENDPOINT_URL" \
    secretsmanager describe-secret \
    --secret-id "$SECRET_NAME_2" \
    >/dev/null 2>&1; then
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME_2" \
        --secret-string "$WEBHOOK_2_PLAIN_SIGNING_SECRET" \
        > /dev/null
else
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager create-secret \
        --name "$SECRET_NAME_2" \
        --secret-string "$WEBHOOK_2_PLAIN_SIGNING_SECRET" \
        > /dev/null
fi

WEBHOOK_2_ENCRYPTED_SECRET=$(encrypt_webhook_secret "$WEBHOOK_2_PLAIN_SIGNING_SECRET")

psql_exec "
    INSERT INTO client_webhooks (id, label, callback_url, encrypted_signing_secret, events, client_api_settings_id)
    VALUES (
        '$WEBHOOK_2_ID',
        '$WEBHOOK_2_LABEL',
        '$WEBHOOK_2_CALLBACK_URL',
        '$WEBHOOK_2_ENCRYPTED_SECRET',
        ARRAY['$WEBHOOK_2_EVENTS'],
        '$API_SETTINGS_ID'
    );
" > /dev/null

print_success "Created webhook 2: $WEBHOOK_2_LABEL (ID: $WEBHOOK_2_ID)"

# Webhook 3: Local - OC
WEBHOOK_3_ID="4b36cba2-d575-4b69-b185-01d1fd8aacbf"
WEBHOOK_3_LABEL="Local - OC"
WEBHOOK_3_CALLBACK_URL="$WH_CALLBACK_OC"
WEBHOOK_3_PLAIN_SIGNING_SECRET="ed33c2d722b8163ea353441b8d4fe2ebed65e158828d26dd66a351e646612711"
WEBHOOK_3_EVENTS="ownership_check.verification_completed"

print_info "Creating webhook 3: $WEBHOOK_3_LABEL"
SECRET_NAME_3="clients/$CLIENT_ID/webhooks/$WEBHOOK_3_ID"

if aws --endpoint-url="$AWS_ENDPOINT_URL" \
    secretsmanager describe-secret \
    --secret-id "$SECRET_NAME_3" \
    >/dev/null 2>&1; then
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME_3" \
        --secret-string "$WEBHOOK_3_PLAIN_SIGNING_SECRET" \
        > /dev/null
else
    aws --endpoint-url="$AWS_ENDPOINT_URL" \
        secretsmanager create-secret \
        --name "$SECRET_NAME_3" \
        --secret-string "$WEBHOOK_3_PLAIN_SIGNING_SECRET" \
        > /dev/null
fi

WEBHOOK_3_ENCRYPTED_SECRET=$(encrypt_webhook_secret "$WEBHOOK_3_PLAIN_SIGNING_SECRET")

psql_exec "
    INSERT INTO client_webhooks (id, label, callback_url, encrypted_signing_secret, events, client_api_settings_id)
    VALUES (
        '$WEBHOOK_3_ID',
        '$WEBHOOK_3_LABEL',
        '$WEBHOOK_3_CALLBACK_URL',
        '$WEBHOOK_3_ENCRYPTED_SECRET',
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
