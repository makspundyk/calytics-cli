#!/bin/bash

# =============================================================================
# Seed Main Client
# =============================================================================
# Ensures the main client (main.client@gmail.com) exists in the database.
# If not, runs the client seeder from calytics-be-admin (npm run seed:clients).
#
# Usage:
#   ./seed-main-client.sh
#
# Environment Variables (optional - same defaults as other seed scripts):
#   POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
#   BE_ADMIN_DIR   - Path to calytics-be-admin (default: script dir ../calytics-be-admin)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
MAIN_CLIENT_EMAIL="${MAIN_CLIENT_EMAIL:-main.client@gmail.com}"
MAIN_CLIENT_SERVICE_EMAIL="${MAIN_CLIENT_SERVICE_EMAIL:-maxpundyk@gmail.com}"
export POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export POSTGRES_USERNAME="${POSTGRES_USERNAME:-$POSTGRES_USER}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-register}"
export POSTGRES_DB="${POSTGRES_DB:-calytics-admin}"
export POSTGRES_NAME="${POSTGRES_NAME:-$POSTGRES_DB}"
BE_ADMIN_DIR="${BE_ADMIN_DIR:-$SCRIPT_DIR/../calytics-be-admin}"

export PAGER=cat

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()    { echo -e "${CYAN}ℹ${NC}  $1"; }
print_success() { echo -e "${GREEN}✓${NC}  $1"; }
print_warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }
print_error()   { echo -e "${RED}✗${NC}  $1"; }

# Returns 0 if main client exists, 1 otherwise.
# CPM refactor (Jun 2026): `clients.email` was dropped. The login email now lives
# on the client's CLIENTS_ADMIN user, linked via the `user_clients` join table —
# matching be-admin's findClientByAdminEmail (users.email -> first user_clients row).
main_client_exists() {
    local id
    id=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -q -c "SELECT uc.client_id FROM user_clients uc JOIN users u ON u.user_id = uc.user_id WHERE u.email = '$MAIN_CLIENT_EMAIL' LIMIT 1;" 2>/dev/null) || true
    [ -n "$id" ]
}

# Ensure main client exists; if not, run client seeder from calytics-be-admin
ensure_main_client() {
    if main_client_exists; then
        print_success "Main client ($MAIN_CLIENT_EMAIL) already exists"
        return 0
    fi
    print_warn "Main client ($MAIN_CLIENT_EMAIL) not found. Running client seeder from calytics-be-admin..."
    if [ ! -d "$BE_ADMIN_DIR" ]; then
        print_error "BE_ADMIN_DIR ($BE_ADMIN_DIR) does not exist. Cannot run client seeder."
        print_info "Create the client manually or run from calytics-be-admin: npm run seed:clients"
        exit 1
    fi
    if [ ! -f "$BE_ADMIN_DIR/dist/domain/seeding/subdomains/clients/seed-clients.js" ]; then
        print_error "calytics-be-admin not built (dist/.../seed-clients.js missing)."
        print_info "Build and run: cd $BE_ADMIN_DIR && npm run build && npm run seed:clients"
        exit 1
    fi
    export AWS_ENVIRONMENT="${AWS_ENVIRONMENT:-local}"
    (cd "$BE_ADMIN_DIR" && npm run seed:clients) || {
        print_error "Client seeder failed. Run manually: cd $BE_ADMIN_DIR && npm run seed:clients"
        exit 1
    }
    if main_client_exists; then
        print_success "Main client created"
    else
        print_error "Client seeder ran but main client still not found."
        exit 1
    fi
}

# service_email used to live on client_api_settings (for mandate PDF notifications).
# It was removed from client_api_settings and now belongs to the separate
# service_contracts (merchant-profile) domain, which is managed via the be-admin API
# (per-merchant + per-product), not seeded here and not required for local FE/data.
# Kept as an explicit, non-breaking no-op so the removal is documented in one place.
ensure_main_client_service_email() {
    print_info "Skipping service_email seed: client_api_settings.service_email was removed in the CPM refactor; service emails now live in the service_contracts API (not part of local seed data)."
}

# Main
print_info "Ensuring main client exists: $MAIN_CLIENT_EMAIL"
ensure_main_client
print_info "Ensuring main client service_email: $MAIN_CLIENT_SERVICE_EMAIL"
ensure_main_client_service_email
print_success "Done."
