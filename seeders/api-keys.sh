#!/bin/bash

# Seeder script for API keys
# This script deletes then recreates all API keys for the main client
# (main.client@gmail.com). No duplicates: every run replaces existing API keys.

set -euo pipefail

# Configuration
CLIENT_EMAIL="main.client@gmail.com"
AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-register}"
POSTGRES_DB="${POSTGRES_DB:-calytics-admin}"

# API Key encryption secret ID (same as in .env)
API_KEY_ENCRYPTION_SECRET_ID="${API_KEY_ENCRYPTION_SECRET_ID:-calytics-be-admin/api-key-encryption}"

# Disable pagers so psql and aws never open less/vim
export PAGER=cat
export AWS_PAGER=""

# API Keys to seed (environment: sandbox)
# Format: PRODUCT_TYPE|API_KEY_VALUE|LABEL
API_KEYS=(
    "DebitGuard|ak_sand_21c0f785e49e88d7c7d5b6a8f19a2402bbb190e2198a6158a7aa30331aa0e2b2|Local - DebitGuard"
    "OwnershipCheck|ak_sand_ff764a4e74ce9c8830c705c73ba57f911bbf4d81b3d63be427dc1641ae3bcb3a|Local - OwnershipCheck"
    "A2A|ak_sand_b0694c75fd1c374d264ae48cfb68469cff5d484257b785e0093f04f60ff7b51f|Local - A2A"
    "CalyticsCollect|ak_sand_917986e01ffd95becf1cbf47cd28c04e02bbf48fbe1caa903389044c3a6d58c9|Local - CalyticsCollect"
    "SmartSwitch|ak_sand_bc35765b987aa342931123986cdf6d2e4eeeffd7d029ef19ca27a1b906f33d06|Local - SmartSwitch"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_section() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Helper function to execute PostgreSQL queries (returns single value, clean output)
psql_exec() {
    local result
    result=$(PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        -t -A -q \
        -c "$1" 2>/dev/null) || true
    echo "$result" | grep -v '^$' | head -1 || true
}

# Helper function to execute PostgreSQL queries with formatted output
psql_query() {
    PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        -c "$1"
}

# Function to encrypt API key using AES-256-GCM (matching ApiKeyCryptoService)
encrypt_api_key() {
    local plain_api_key="$1"
    local encryption_secret="$2"
    
    # Generate SHA256 hash of the secret to get the encryption key (32 bytes)
    local encryption_key
    encryption_key=$(echo -n "$encryption_secret" | openssl dgst -sha256 -binary | xxd -p -c 64)
    
    # Generate random IV (12 bytes for GCM)
    local iv
    iv=$(openssl rand -hex 12)
    
    # Encrypt using AES-256-GCM
    # Note: openssl enc doesn't support GCM directly in older versions,
    # so we use a Node.js one-liner for proper AES-256-GCM encryption
    local encrypted
    encrypted=$(node -e "
        const crypto = require('crypto');
        const key = Buffer.from('${encryption_key}', 'hex');
        const iv = Buffer.from('${iv}', 'hex');
        const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
        const encrypted = Buffer.concat([cipher.update('${plain_api_key}', 'utf8'), cipher.final()]);
        const authTag = cipher.getAuthTag();
        const result = Buffer.concat([iv, authTag, encrypted]).toString('base64');
        console.log(result);
    ")
    
    echo "$encrypted"
}

# Step 1: Get client ID by email
print_section "Step 1: Getting Client Information"
print_info "Looking up client ID for email: $CLIENT_EMAIL"
# CPM refactor (Jun 2026): client login identity moved out of `clients` into the
# `users` table. `clients.email` was dropped; the login email now lives on the
# CLIENTS_ADMIN user, linked to its client via the `user_clients` join table.
CLIENT_ID=$(psql_exec "SELECT uc.client_id FROM user_clients uc JOIN users u ON u.user_id = uc.user_id WHERE u.email = '$CLIENT_EMAIL' LIMIT 1;")

if [ -z "$CLIENT_ID" ]; then
    print_error "Client with email $CLIENT_EMAIL not found!"
    exit 1
fi

print_success "Found client ID: $CLIENT_ID"

# Step 2: Get encryption secret from AWS Secrets Manager
print_section "Step 2: Getting Encryption Secret"
print_info "Fetching encryption secret from AWS Secrets Manager..."

ENCRYPTION_SECRET=$(aws --endpoint-url="$AWS_ENDPOINT_URL" \
    secretsmanager get-secret-value \
    --secret-id "$API_KEY_ENCRYPTION_SECRET_ID" \
    --query 'SecretString' \
    --output text 2>/dev/null) || true

if [ -z "$ENCRYPTION_SECRET" ]; then
    print_error "Could not fetch encryption secret from AWS Secrets Manager!"
    print_info "Make sure the secret '$API_KEY_ENCRYPTION_SECRET_ID' exists in LocalStack."
    exit 1
fi

print_success "Encryption secret retrieved successfully"

# Step 3: Clean existing API keys for this client
print_section "Step 3: Cleaning Existing API Keys"
print_info "Removing existing API keys from database and AWS API Gateway..."

# Delete from database first
psql_exec "DELETE FROM api_keys WHERE client_id = '$CLIENT_ID';" > /dev/null
print_success "Cleaned API keys from database"

# Get ALL API Gateway keys for this client (by name pattern)
print_info "Cleaning up API Gateway keys..."
ALL_AWS_KEYS=$(aws --endpoint-url="$AWS_ENDPOINT_URL" \
    apigateway get-api-keys \
    --query "items[?contains(name, '$CLIENT_ID')].id" \
    --output text 2>/dev/null) || true

if [ -n "$ALL_AWS_KEYS" ]; then
    for aws_key_id in $ALL_AWS_KEYS; do
        if [ -n "$aws_key_id" ]; then
            print_info "Deleting API Gateway key: $aws_key_id"
            aws --endpoint-url="$AWS_ENDPOINT_URL" \
                apigateway delete-api-key \
                --api-key "$aws_key_id" \
                2>/dev/null || true
        fi
    done
    print_success "Cleaned all API Gateway keys for this client"
else
    print_info "No API Gateway keys found for this client"
fi

# Step 4: Create API keys
print_section "Step 4: Creating API Keys"

# GNU date uses -d, BSD/macOS date uses -v — try GNU first, fall back to BSD.
# CPM/DI refactor (Jun 2026): every (client, product, environment) now carries TWO
# api_keys rows — a CLIENT_USAGE key (client-revealable, labelled, 1-year expiry)
# and a CLIENT_SYSTEM key (platform-internal, never revealed to CLIENT_USERs, no
# label, 10-year expiry to match be-admin SYSTEM_KEY_EXPIRY_YEARS). The api_keys
# table gained `api_key_type` + `status`, and renamed expiresAt/createdAt to
# snake_case. See be-admin ApiKeyType enum + api-key.service.ts.
EXPIRES_AT_USAGE=$(date -u -d "+1 year" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date -u -v+1y +"%Y-%m-%d %H:%M:%S")
EXPIRES_AT_SYSTEM=$(date -u -d "+10 years" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date -u -v+10y +"%Y-%m-%d %H:%M:%S")

# Provision one API Gateway key + encrypted DB row for a (product, key type).
# Args: 1=product_type 2=api_key_value 3=label 4=api_key_type 5=expires_at 6=external_usage_plan_id
create_api_key() {
    ck_product="$1"; ck_value="$2"; ck_label="$3"; ck_type="$4"; ck_expires="$5"; ck_plan="$6"
    ck_id=$(uuidgen | tr '[:upper:]' '[:lower:]')

    # System keys carry no user-facing label (be-admin DI rules).
    if [ "$ck_type" = "CLIENT_SYSTEM" ]; then
        ck_label_sql="NULL"
    else
        ck_label_sql="'$ck_label'"
    fi

    # Create API key in AWS API Gateway. The clientId tag is required by
    # ApiGatewayApiKeyService to resolve the client; apiKeyType is restored onto
    # the DynamoDB lookup record on re-seed (be-admin DI-FR-17).
    print_info "Creating API Gateway key for $ck_product ($ck_type)..."
    ck_aws_response=$(aws --endpoint-url="$AWS_ENDPOINT_URL" \
        apigateway create-api-key \
        --name "client-${CLIENT_ID}-apiKey-${ck_product}-${ck_type}-local" \
        --enabled \
        --value "$ck_value" \
        --tags "clientId=${CLIENT_ID},apiKeyType=${ck_type}" \
        --output json 2>/dev/null) || true

    if [ -z "$ck_aws_response" ]; then
        print_error "Failed to create API Gateway key for $ck_product ($ck_type)"
        return 1
    fi

    ck_aws_id=$(echo "$ck_aws_response" | node -e "
        const data = require('fs').readFileSync(0, 'utf8');
        console.log(JSON.parse(data).id);
    ")
    if [ -z "$ck_aws_id" ]; then
        print_error "Failed to get API Gateway key ID for $ck_product ($ck_type)"
        return 1
    fi
    print_success "Created API Gateway key: $ck_aws_id"

    # Attach to usage plan (if exists and not the 'aczpi1gfrd' placeholder)
    if [ -n "$ck_plan" ] && [ "$ck_plan" != "aczpi1gfrd" ]; then
        print_info "Attaching to usage plan: $ck_plan"
        aws --endpoint-url="$AWS_ENDPOINT_URL" \
            apigateway create-usage-plan-key \
            --usage-plan-id "$ck_plan" \
            --key-id "$ck_aws_id" \
            --key-type "API_KEY" \
            2>/dev/null || true
    fi

    ck_encrypted=$(encrypt_api_key "$ck_value" "$ENCRYPTION_SECRET")
    if [ -z "$ck_encrypted" ]; then
        print_error "Failed to encrypt API key for $ck_product ($ck_type)"
        return 1
    fi

    psql_exec "
        INSERT INTO api_keys (
            id,
            environment,
            label,
            aws_key_id,
            expires_at,
            client_id,
            created_at,
            scopes,
            encrypted_api_key,
            product_type,
            api_key_type,
            status
        ) VALUES (
            '$ck_id',
            'Sandbox',
            $ck_label_sql,
            '$ck_aws_id',
            '$ck_expires',
            '$CLIENT_ID',
            NOW(),
            ARRAY['debit_guard', 'ownership_check', 'a2a']::text[],
            '$ck_encrypted',
            '$ck_product',
            '$ck_type',
            'Active'
        );
    " > /dev/null

    print_success "Created $ck_type API key for $ck_product"
    echo "   API Key ID: $ck_id"
    echo "   AWS Key ID: $ck_aws_id"
    echo "   Expires At: $ck_expires"
}

for API_KEY_DATA in "${API_KEYS[@]}"; do
    IFS='|' read -r PRODUCT_TYPE API_KEY_VALUE LABEL <<< "$API_KEY_DATA"

    print_info "Processing API keys for: $PRODUCT_TYPE"

    # Check if subscription exists for this product
    SUBSCRIPTION_EXISTS=$(psql_exec "
        SELECT id FROM client_subscriptions
        WHERE client_id = '$CLIENT_ID'
        AND product_type = '$PRODUCT_TYPE'
        AND is_active = true;
    ")

    if [ -z "$SUBSCRIPTION_EXISTS" ]; then
        print_warn "No active subscription found for $PRODUCT_TYPE. Skipping..."
        continue
    fi

    # Get product plan for external_usage_plan_id
    EXTERNAL_USAGE_PLAN_ID=$(psql_exec "
        SELECT external_usage_plan_id FROM product_plans
        WHERE client_id = '$CLIENT_ID'
        AND product_type = '$PRODUCT_TYPE'
        ORDER BY created_at DESC
        LIMIT 1;
    ")

    # CLIENT_USAGE key — the deterministic local key value clients use directly.
    create_api_key "$PRODUCT_TYPE" "$API_KEY_VALUE" "$LABEL" "CLIENT_USAGE" "$EXPIRES_AT_USAGE" "$EXTERNAL_USAGE_PLAN_ID" || continue
    echo "   Label: $LABEL"
    echo "   API Key Value: $API_KEY_VALUE"

    # CLIENT_SYSTEM key — platform-internal, distinct deterministic value so local
    # runs are reproducible and the value never collides with the usage key.
    SYSTEM_KEY_VALUE="ak_sys_sand_$(printf 'system-%s-%s' "$CLIENT_ID" "$PRODUCT_TYPE" | openssl dgst -sha256 | awk '{print $NF}')"
    create_api_key "$PRODUCT_TYPE" "$SYSTEM_KEY_VALUE" "" "CLIENT_SYSTEM" "$EXPIRES_AT_SYSTEM" "$EXTERNAL_USAGE_PLAN_ID" || true
done

# Verification: Display final state
print_section "Verification: Final State"

echo "API Keys:"
psql_query "
    SELECT
        id,
        product_type,
        api_key_type,
        status,
        environment,
        label,
        aws_key_id,
        expires_at,
        created_at
    FROM api_keys
    WHERE client_id = '$CLIENT_ID'
    ORDER BY product_type, api_key_type;
"

echo ""
echo "AWS API Gateway Keys:"
aws --endpoint-url="$AWS_ENDPOINT_URL" \
    apigateway get-api-keys \
    --query "items[?contains(name, '$CLIENT_ID')].{Name:name, ID:id, Enabled:enabled}" \
    --output table 2>/dev/null || echo "Could not fetch API Gateway keys"

print_success "API keys seeder completed successfully!"
echo ""
echo "API Keys created:"
echo "  - DebitGuard:      ak_sand_21c0f785e49e88d7c7d5b6a8f19a2402bbb190e2198a6158a7aa30331aa0e2b2"
echo "  - OwnershipCheck:  ak_sand_ff764a4e74ce9c8830c705c73ba57f911bbf4d81b3d63be427dc1641ae3bcb3a"
echo "  - A2A:             ak_sand_b0694c75fd1c374d264ae48cfb68469cff5d484257b785e0093f04f60ff7b51f"
echo "  - CalyticsCollect: ak_sand_917986e01ffd95becf1cbf47cd28c04e02bbf48fbe1caa903389044c3a6d58c9"
echo "  - SmartSwitch:     ak_sand_bc35765b987aa342931123986cdf6d2e4eeeffd7d029ef19ca27a1b906f33d06"
