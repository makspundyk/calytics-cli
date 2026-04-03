#!/bin/bash

# Seeder script for product plans and subscriptions
# This script deletes then recreates all product plans and subscriptions for the client
# (main.client@gmail.com). No duplicates: every run replaces existing data.

set -euo pipefail

# Configuration
CLIENT_EMAIL="main.client@gmail.com"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-register}"
POSTGRES_DB="${POSTGRES_DB:-calytics-admin}"

# Disable pager so psql never opens less/vim
export PAGER=cat

# Default product plan values
DEFAULT_PRICE=200
DEFAULT_REQUESTS_LIMIT=1000
DEFAULT_TIMEFRAME=1
DEFAULT_TIMEFRAME_TYPE="MONTH"
DEFAULT_API_ID="aczpi1gfrd"

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

# Helper function to execute PostgreSQL queries (returns multiple values)
psql_exec_multi() {
    local result
    result=$(PGPASSWORD="$POSTGRES_PASSWORD" psql \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        -t -A -q \
        -c "$1" 2>/dev/null) || true
    echo "$result" | grep -v '^$' || true
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

# Step 1: Get client ID by email
print_section "Step 1: Getting Client Information"
print_info "Looking up client ID for email: $CLIENT_EMAIL"
CLIENT_ID=$(psql_exec "SELECT id FROM clients WHERE email = '$CLIENT_EMAIL';")

if [ -z "$CLIENT_ID" ]; then
    print_error "Client with email $CLIENT_EMAIL not found!"
    exit 1
fi

print_success "Found client ID: $CLIENT_ID"

# Step 2: Get available product types from database enum
print_section "Step 2: Detecting Available Product Types"
print_info "Fetching available product types from database enum..."

# Get enum values from PostgreSQL
AVAILABLE_PRODUCTS=$(psql_exec_multi "
    SELECT unnest(enum_range(NULL::product_plans_product_type_enum))::text;
")

if [ -z "$AVAILABLE_PRODUCTS" ]; then
    print_error "Could not fetch product types from database!"
    exit 1
fi

# Convert to array
readarray -t PRODUCTS <<< "$AVAILABLE_PRODUCTS"

print_success "Found ${#PRODUCTS[@]} product types: ${PRODUCTS[*]}"

# Step 3: Delete existing subscriptions and product plans for this client
print_section "Step 3: Deleting Existing Subscriptions and Product Plans"
psql_exec "DELETE FROM client_subscriptions WHERE client_id = '$CLIENT_ID';" > /dev/null
psql_exec "DELETE FROM product_plans WHERE client_id = '$CLIENT_ID';" > /dev/null
print_success "Deleted existing subscriptions and product plans"

# Step 4: Create product plans for each product
print_section "Step 4: Creating Product Plans"

for PRODUCT in "${PRODUCTS[@]}"; do
    print_info "Creating product plan for $PRODUCT..."
    PLAN_NAME="Mainclient-$PRODUCT-Local"
    psql_exec "
        INSERT INTO product_plans (
            id,
            name,
            product_type,
            price,
            requests_limit,
            external_usage_plan_id,
            timeframe,
            timeframe_type,
            client_id,
            created_at,
            updated_at
        ) VALUES (
            gen_random_uuid(),
            '$PLAN_NAME',
            '$PRODUCT',
            $DEFAULT_PRICE,
            $DEFAULT_REQUESTS_LIMIT,
            '$DEFAULT_API_ID',
            $DEFAULT_TIMEFRAME,
            '$DEFAULT_TIMEFRAME_TYPE',
            '$CLIENT_ID',
            NOW(),
            NOW()
        );
    " > /dev/null
    NEW_PLAN_ID=$(psql_exec "SELECT id FROM product_plans WHERE client_id = '$CLIENT_ID' AND product_type = '$PRODUCT' ORDER BY created_at DESC LIMIT 1;")
    print_success "Created product plan for $PRODUCT (ID: $NEW_PLAN_ID)"
done

# Step 5: Create subscriptions for each product plan
print_section "Step 5: Creating Subscriptions"

for PRODUCT in "${PRODUCTS[@]}"; do
    print_info "Creating subscription for $PRODUCT..."
    PLAN_ID=$(psql_exec "SELECT id FROM product_plans WHERE client_id = '$CLIENT_ID' AND product_type = '$PRODUCT' ORDER BY created_at ASC LIMIT 1;")
    if [ -z "$PLAN_ID" ]; then
        print_error "No product plan found for $PRODUCT. Skipping subscription."
        continue
    fi
    STARTED_AT=$(date -u +"%Y-%m-%d %H:%M:%S")
    EXPIRES_AT=$(date -u -d "+1 year" +"%Y-%m-%d %H:%M:%S")
    NEW_SUBSCRIPTION_ID=$(psql_exec "
        INSERT INTO client_subscriptions (
            id,
            is_active,
            product_type,
            started_at,
            expires_at,
            client_id,
            product_plan_id,
            created_at,
            updated_at
        ) VALUES (
            gen_random_uuid(),
            true,
            '$PRODUCT',
            '$STARTED_AT',
            '$EXPIRES_AT',
            '$CLIENT_ID',
            '$PLAN_ID',
            NOW(),
            NOW()
        )
        RETURNING id;
    ")
    print_success "Created subscription for $PRODUCT (ID: $NEW_SUBSCRIPTION_ID)"
done

# Verification: Display final state
print_section "Verification: Final State"

echo "Product Plans:"
psql_query "
    SELECT 
        id,
        name,
        product_type,
        price,
        requests_limit,
        timeframe || ' ' || timeframe_type as timeframe,
        created_at
    FROM product_plans 
    WHERE client_id = '$CLIENT_ID'
    ORDER BY product_type;
"

echo ""
echo "Subscriptions:"
psql_query "
    SELECT 
        cs.id,
        cs.product_type,
        cs.is_active,
        cs.started_at,
        cs.expires_at,
        cs.product_plan_id
    FROM client_subscriptions cs
    WHERE cs.client_id = '$CLIENT_ID'
    ORDER BY cs.product_type;
"

print_success "Seeder completed successfully! All product plans and subscriptions have been deleted and recreated."
