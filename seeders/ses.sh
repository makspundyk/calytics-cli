#!/bin/bash

# =============================================================================
# Seed LocalStack SES – Verify sender identity for local email
# =============================================================================
# Verifies the local sender identity (local@calytics.local) in LocalStack SES
# so that calytics-a2a can send mandate notification emails locally without
# "Did not have authority to send from" errors.
#
# Usage:
#   ./seed-localstack-ses.sh
#
# Environment Variables (optional):
#   AWS_ENDPOINT_URL  - LocalStack endpoint (default: http://localhost:4566)
#   AWS_REGION        - AWS region (default: eu-central-1)
#   SES_FROM_EMAIL    - Identity to verify (default: local@calytics.local)
# =============================================================================

set -euo pipefail

AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
SES_FROM_EMAIL="${SES_FROM_EMAIL:-local@calytics.local}"
export AWS_PAGER=""

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_info()    { echo -e "${CYAN}ℹ${NC}  $1"; }
print_success() { echo -e "${GREEN}✓${NC}  $1"; }
print_warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }

# Verify email identity in LocalStack SES (required for SendEmail/SendRawEmail)
print_info "Verifying SES identity: $SES_FROM_EMAIL at $AWS_ENDPOINT_URL"
if aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
    ses verify-email-identity --email-address "$SES_FROM_EMAIL" 2>/dev/null; then
    print_success "SES identity $SES_FROM_EMAIL verified (local email will work)"
else
    # Idempotent: identity may already exist
    if aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
        ses list-identities --output text 2>/dev/null | grep -q "$SES_FROM_EMAIL"; then
        print_success "SES identity $SES_FROM_EMAIL already verified"
    else
        print_warn "SES verify/list failed (is LocalStack running with SES?). Emails will still be written to .tmp/emails/"
    fi
fi
