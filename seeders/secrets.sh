#!/bin/bash

# =============================================================================
# Seed LocalStack Secrets
# =============================================================================
# This script deletes then recreates all required secrets in LocalStack
# (AWS Secrets Manager) for local development. No duplicates: every run
# replaces existing secrets with the same values.
#
# Usage:
#   ./seed-localstack-secrets.sh
#
# Environment Variables (optional - defaults provided):
#   AWS_ENDPOINT_URL    - LocalStack endpoint (default: http://localhost:4566)
#   AWS_REGION          - AWS region (default: eu-central-1)
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
AWS_REGION="${AWS_REGION:-eu-central-1}"

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

# Delete then create a secret (idempotent: no duplicates, same state every run)
create_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local description="${3:-}"
    
    print_info "Recreating secret: ${BOLD}$secret_name${NC}"
    
    # Delete if exists (ignore errors)
    aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
        secretsmanager delete-secret \
        --secret-id "$secret_name" \
        --force-delete-without-recovery \
        2>/dev/null || true
    
    # Create fresh
    aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
        secretsmanager create-secret \
        --name "$secret_name" \
        --secret-string "$secret_value" \
        > /dev/null
    print_success "Created: $secret_name"
}

# =============================================================================
# Main Script
# =============================================================================

print_header "🔐 Seeding LocalStack Secrets"

echo -e "Configuration:"
echo -e "  Endpoint: ${CYAN}$AWS_ENDPOINT_URL${NC}"
echo -e "  Region:   ${CYAN}$AWS_REGION${NC}"
echo ""

# -----------------------------------------------------------------------------
# Revolut Credentials
# -----------------------------------------------------------------------------
print_header "Revolut Credentials"

create_secret \
    "calytics/calytics-be/local/revolut/credentials" \
    '{"access_token":"test","client_assertion":"test"}'

create_secret \
    "calytics/calytics-be/local/revolut/static-credentials" \
    '{"refresh_token":"oa_sand_h0r7qvVtkR40FqVERzlAjpFLR-E_tf-22bhktoQoQJE","private_key":"-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDcGlNagzawJxI+\nyej0LeY8Jzm/IXUln6HCSTR7WryKDhddPKAsQLRp7GUTgWstraKBhs3vzTCXnDv/\nLFRZ4k35fkirUq/z/safPzP9bM3kagjBBjZX7/UrZfJliGoBUskTCQEYSfiVIbG9\nQ68JehFX23i04Hj+BKwKirvjcFdVIpP6S+7AAmXp5+SrpHzNmZe3wWg87zbQETuV\nyG+yUjLGUt+6xchHtmuHVPYtwFEiTD2SyscVIxwfbV/O0BA2/4jcn/rDqvjniWZC\ngi8zN+ZFLmKl/7mqKWzL6hE79ZCfS/tDnWYoeij1FKZEEligle37c226gB1yU7/v\n6Ar0wrLvAgMBAAECggEAB2TprfMV2unFHCTjquhWgWjT8M7VRP6i4Yhct1QqB1Kd\nMv2pZ93YnG0GTEHJxvlmqdv3KSTcirYDR07xmn9sHS3tOmGHFbcBFzJ5Xacnwjz/\nBEpgIv4ltLUyZSTQYtupc6FBedO/rSA6UgsRuKDIL7UTeLLIfcghu3eZA6AE3xBA\nAhviiEGqO8cgaaLqINbZsnQJ9p7s253zbJn5SeXZHYi8SPxU1NuH0uSrizmEP6/7\np7HSaipk10MYyy14vB2J6q8WPwK42g0QGisKtgWXspLPQKXLqCvAIymPWHRW8uih\nFRC2/C+45eEPFD+EKIna5gjlP7k60gwnM6L41VscmQKBgQD7VVha+DwvcB2lvI+F\np1ueHUbP6Tg+9uxfKD/A0Vzch+mu8GL7ZZ8FK70Fq3EBBDLy3AucwKgDBLbmaC/7\nwL8HO/S0uVdJ94wOsnrLjf8vmaYE/H6en+7e3lOLPU4xPAq12lgPjNo1+DTb2HEQ\nf02f+VR9lUfBzzmNarADeInZFQKBgQDgMIiHejv7UUjFLqWF9uG0xZH+2BaHnjbq\n79UgsEzt+kpv9ernGci35SrmU+iqA3vGs3ltEtifIe3aiVxhBO3UqUXjstpE19Bx\nHcpvpzOhS3gHrmvKsoxgZZ6aiPsVNrtSn+e7Cu89Qbbd12z87p+dl6LqpbAO+rMc\nBrDcxiQU8wKBgQCWEB0TI8f7ovtwq6cd7BD91QkktmFI5vG21zdJjzfczKGwPAM9\niy1pTvYrXnO4YaNx8gRU8YrfUn9KDscnj6v/S8MN7OO7XDyZweMjioLlDt5bd866\nM0/Sbfh/2HjJWMokTlvp3PWk56/X2+GWMgxNCfdyjCEuDOaWEy9Iwz27CQKBgQC1\nYa7kZVnoIECPAAl9VFwSJJLVK8E2oiPuenHly53CIHFfGgieRzckyW2nAhZIjx7y\niTxhqhDG1u2YlO+/svw0xWs9KPP9JNqI2kBxi0ZzZhrLpCujyEdYqn7iqpbx9+Eg\nnS0gIF2lIuivnV6ZWPqcxxVRYRILXHvS3frz8/83TwKBgD4WP562xnk0dclprJWn\nfKiYGMvMl8ARxJmLkXlJgzAwk/0blczMLl49eQm5N20AobyL8yOY26UsRcPuP8GD\nAxzl2KjFW956iutiCIbazF5GuJP5/kcK5sK7iL717vm/KYJmcbGOzy9j7CIXOgxd\nFArpBS1t7Q75WlEmoc4QbwHB\n-----END PRIVATE KEY-----","client_id":"oYz3gpfeDe109pkCBnBEB4ojeRt2HamWoi5MdcfKTd8","redirect_domain":"google.com"}'

# -----------------------------------------------------------------------------
# Qonto Credentials
# -----------------------------------------------------------------------------
print_header "Qonto Credentials"

create_secret \
    "calytics/qonto/credentials" \
    '{"refresh_token":"ory_rt_5pjrQ717hmO3KWc1v2VLlb-VbRYbMVZNipvTtgIT274.w7xdAK4UdkDO9bY3o0CjUzI2b4T0AotNBeECx235Wgk","access_token":"ory_at_vekP5R_URvkx5M2Waex8v72zs_M3649uJ3orcuEdXpw.zw-bC3DiOFeF0jaj2vMAryLirYtbNJYsAJ1EIkCze98","expires_at":0}'

create_secret \
    "calytics/qonto/static-credentials" \
    '{"client_id":"9f1fddf2-0c3e-443e-ade9-fd9f6abd93b0","client_secret":"sEYIOlx0Zr4B6hjCGr3q46pwdJ"}'

# -----------------------------------------------------------------------------
# FinAPI Credentials (synced from AWS sandbox)
# -----------------------------------------------------------------------------
print_header "FinAPI Credentials"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "$SCRIPT_DIR/sync-finapi-sandbox-to-local.sh" ]; then
    print_info "Syncing FinAPI sandbox secrets from AWS..."
    if "$SCRIPT_DIR/sync-finapi-sandbox-to-local.sh"; then
        print_success "FinAPI sandbox secrets synced successfully"
    else
        print_warn "Failed to sync FinAPI sandbox secrets from AWS, creating placeholders..."
        create_secret \
            "calytics/calytics-be/local/finapi/credentials" \
            '{"access_token":"test-access-token"}'
        create_secret \
            "calytics/calytics-be/local/finapi/static-credentials" \
            '{"client_id":"454ecb6c-0ee4-4505-a7f5-ca9907366eee","client_secret":"e7b4afd1-2373-4884-84c0-f17fea2b6ced"}'
    fi
else
    print_warn "sync-finapi-sandbox-to-local.sh not found, creating placeholder secrets..."
    create_secret \
        "calytics/calytics-be/local/finapi/credentials" \
        '{"access_token":"test-access-token"}'
    create_secret \
        "calytics/calytics-be/local/finapi/static-credentials" \
        '{"client_id":"454ecb6c-0ee4-4505-a7f5-ca9907366eee","client_secret":"e7b4afd1-2373-4884-84c0-f17fea2b6ced"}'
fi

# -----------------------------------------------------------------------------
# Bright Data Proxy Credentials
# -----------------------------------------------------------------------------
print_header "Bright Data Proxy Credentials"

# Sync from production if available, otherwise create placeholder
print_info "Attempting to sync Bright Data credentials from production..."
if BRD_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "calytics/prod/bright-data/credentials" \
    --region "$AWS_REGION" \
    --query 'SecretString' --output text 2>/dev/null); then
    create_secret \
        "calytics/local/bright-data/credentials" \
        "$BRD_SECRET"
    print_success "Bright Data credentials synced from production"
else
    print_warn "Could not sync from production, creating placeholder..."
    create_secret \
        "calytics/local/bright-data/credentials" \
        '{"username":"brd-customer-placeholder","password":"placeholder-password"}'
fi

# -----------------------------------------------------------------------------
# A2A FinAPI Credentials (calytics-a2a local)
# -----------------------------------------------------------------------------
print_header "A2A FinAPI Credentials"

# Static credentials: sandbox client ID/secret, URLs, encryption key, webform callback secret
create_secret \
    "calytics/a2a/local/finapi/static-credentials" \
    '{"client_id":"454ecb6c-0ee4-4505-a7f5-ca9907366eee","client_secret":"e7b4afd1-2373-4884-84c0-f17fea2b6ced","base_url":"https://sandbox.finapi.io","webform_base_url":"https://webform-sandbox.finapi.io","encryption_key":"rYRNwV/OpPP8eFC8VusLk4+ZsUWhHAayPvEN+1WiB30=","webform_callback_secret":"test-callback-secret"}'

# Dynamic credentials (tokens; refreshed by the system in use)
create_secret \
    "calytics/a2a/local/finapi/credentials" \
    '{"access_token":"test-access-token","refresh_token":"test-refresh-token","expires_at":9999999999999}'

# -----------------------------------------------------------------------------
# API Key Encryption (calytics-be-admin)
# -----------------------------------------------------------------------------
print_header "API Key Encryption"

create_secret \
    "calytics-be-admin/api-key-encryption" \
    'local-dev-api-key-encryption-secret-32chars!'

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "📋 Summary"

echo -e "All secrets have been deleted and recreated in LocalStack."
echo ""
echo -e "Secrets present:"
aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
    secretsmanager list-secrets \
    --query 'SecretList[].Name' \
    --output text 2>/dev/null | tr '\t' '\n' | sort | sed 's/^/  - /'

echo ""
print_success "LocalStack secrets seeding completed! (delete-then-recreate)"
