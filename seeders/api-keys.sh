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
CLIENT_ID=$(psql_exec "SELECT id FROM clients WHERE email = '$CLIENT_EMAIL';")

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

EXPIRES_AT=$(date -u -d "+1 year" +"%Y-%m-%d %H:%M:%S")

for API_KEY_DATA in "${API_KEYS[@]}"; do
    IFS='|' read -r PRODUCT_TYPE API_KEY_VALUE LABEL <<< "$API_KEY_DATA"
    
    print_info "Processing API key for: $PRODUCT_TYPE"
    
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
    
    # Generate UUID for the API key record
    API_KEY_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    
    # Create API key in AWS API Gateway with clientId tag
    # The clientId tag is required by ApiGatewayApiKeyService to resolve the client
    print_info "Creating API Gateway key for $PRODUCT_TYPE..."
    AWS_KEY_RESPONSE=$(aws --endpoint-url="$AWS_ENDPOINT_URL" \
        apigateway create-api-key \
        --name "client-${CLIENT_ID}-apiKey-${PRODUCT_TYPE}-local" \
        --enabled \
        --value "$API_KEY_VALUE" \
        --tags "clientId=${CLIENT_ID}" \
        --output json 2>/dev/null) || true
    
    if [ -z "$AWS_KEY_RESPONSE" ]; then
        print_error "Failed to create API Gateway key for $PRODUCT_TYPE"
        continue
    fi
    
    AWS_KEY_ID=$(echo "$AWS_KEY_RESPONSE" | node -e "
        const data = require('fs').readFileSync(0, 'utf8');
        const json = JSON.parse(data);
        console.log(json.id);
    ")
    
    if [ -z "$AWS_KEY_ID" ]; then
        print_error "Failed to get API Gateway key ID for $PRODUCT_TYPE"
        continue
    fi
    
    print_success "Created API Gateway key: $AWS_KEY_ID"
    
    # Attach to usage plan (if exists and not 'aczpi1gfrd' placeholder)
    if [ -n "$EXTERNAL_USAGE_PLAN_ID" ] && [ "$EXTERNAL_USAGE_PLAN_ID" != "aczpi1gfrd" ]; then
        print_info "Attaching to usage plan: $EXTERNAL_USAGE_PLAN_ID"
        aws --endpoint-url="$AWS_ENDPOINT_URL" \
            apigateway create-usage-plan-key \
            --usage-plan-id "$EXTERNAL_USAGE_PLAN_ID" \
            --key-id "$AWS_KEY_ID" \
            --key-type "API_KEY" \
            2>/dev/null || true
    fi
    
    # Encrypt the API key
    print_info "Encrypting API key..."
    ENCRYPTED_API_KEY=$(encrypt_api_key "$API_KEY_VALUE" "$ENCRYPTION_SECRET")
    
    if [ -z "$ENCRYPTED_API_KEY" ]; then
        print_error "Failed to encrypt API key for $PRODUCT_TYPE"
        continue
    fi
    
    # Insert into database
    print_info "Inserting API key into database..."
    psql_exec "
        INSERT INTO api_keys (
            id,
            environment,
            label,
            aws_key_id,
            \"expiresAt\",
            client_id,
            \"createdAt\",
            scopes,
            encrypted_api_key,
            product_type
        ) VALUES (
            '$API_KEY_ID',
            'Sandbox',
            '$LABEL',
            '$AWS_KEY_ID',
            '$EXPIRES_AT',
            '$CLIENT_ID',
            NOW(),
            ARRAY['debit_guard', 'ownership_check', 'a2a']::text[],
            '$ENCRYPTED_API_KEY',
            '$PRODUCT_TYPE'
        );
    " > /dev/null
    
    print_success "Created API key for $PRODUCT_TYPE"
    echo "   API Key ID: $API_KEY_ID"
    echo "   AWS Key ID: $AWS_KEY_ID"
    echo "   Label: $LABEL"
    echo "   Expires At: $EXPIRES_AT"
    echo "   API Key Value: $API_KEY_VALUE"
done

# Verification: Display final state
print_section "Verification: Final State"

echo "API Keys:"
psql_query "
    SELECT 
        id,
        product_type,
        environment,
        label,
        aws_key_id,
        \"expiresAt\" as expires_at,
        \"createdAt\" as created_at
    FROM api_keys 
    WHERE client_id = '$CLIENT_ID'
    ORDER BY product_type;
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
