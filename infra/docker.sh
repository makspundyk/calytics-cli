#!/bin/bash

# =============================================================================
# LocalStack Prep – Infrastructure (Docker)
# =============================================================================
#
# Starts LocalStack and all required Docker containers. Run this before
# local-start-be-admin.sh (or any product prep script).
#
# What it does:
#   1. Starts LocalStack container (AWS emulation)
#   2. Starts other Docker containers (e.g. Postgres from calytics-be-admin)
#
# Usage:
#   ./local-start-infra.sh
#
# Environment Variables (optional):
#   DOCKER_CONTAINER    - LocalStack container name (default: localstack_main)
#   POSTGRES_CONTAINER  - Postgres container name (default: calytics_postgres)
#   BE_ADMIN_DIR        - Path to calytics-be-admin for compose (default: ../calytics-be-admin)
#   LOCALSTACK_WAIT     - Seconds to wait before checking LocalStack (default: 3)
#   AWS_ENDPOINT_URL    - LocalStack endpoint (default: http://localhost:4566)
#   AWS_REGION          - AWS region (default: eu-central-1)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"
DOCKER_CONTAINER="${DOCKER_CONTAINER:-localstack_main}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-calytics_postgres}"
BE_ADMIN_DIR="${BE_ADMIN_DIR:-$SCRIPT_DIR/../calytics-be-admin}"
LOCALSTACK_WAIT="${LOCALSTACK_WAIT:-3}"
export PAGER=cat
export AWS_PAGER=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

print_banner() {
    echo -e "${MAGENTA}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                   ║"
    echo "║   🐳 LocalStack & Docker – Infrastructure Prep                     ║"
    echo "║                                                                   ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    local step="$1"
    local title="$2"
    echo -e "\n${BLUE}${BOLD}┌─────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}${BOLD}│  ${CYAN}Step $step:${NC} ${BOLD}$title${NC}"
    echo -e "${BLUE}${BOLD}└─────────────────────────────────────────────────────────────────────┘${NC}\n"
}

print_info()    { echo -e "${CYAN}ℹ${NC}  $1"; }
print_success() { echo -e "${GREEN}✓${NC}  $1"; }
print_warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }
print_error()   { echo -e "${RED}✗${NC}  $1"; }
print_step()    { echo -e "${MAGENTA}▸${NC}  $1"; }

print_config() {
    echo -e "${DIM}Configuration:${NC}"
    echo -e "  ${DIM}├─${NC} LocalStack:       ${CYAN}$DOCKER_CONTAINER${NC} @ $AWS_ENDPOINT_URL"
    echo -e "  ${DIM}├─${NC} Postgres:         ${CYAN}$POSTGRES_CONTAINER${NC}"
    echo -e "  ${DIM}└─${NC} BE Admin dir:     ${CYAN}$BE_ADMIN_DIR${NC}"
    echo ""
}

# Ensure LocalStack container exists — create it automatically if missing
check_docker_container() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER}$"; then
        print_warn "Docker container '$DOCKER_CONTAINER' not found — creating it"
        docker run -d \
            -p 4566:4566 \
            -p 4510-4559:4510-4559 \
            --name "$DOCKER_CONTAINER" \
            -e PERSISTENCE=1 \
            -v localstack_data:/var/lib/localstack \
            localstack/localstack:3.8
        print_success "LocalStack container created (localstack:3.8)"
    fi
}

# Start LocalStack and wait until it responds
start_localstack() {
    check_docker_container
    print_step "Starting container: $DOCKER_CONTAINER"
    docker start "$DOCKER_CONTAINER" 2>/dev/null || true
    print_info "Waiting ${LOCALSTACK_WAIT}s for LocalStack to initialize..."
    sleep "$LOCALSTACK_WAIT"

    local max_attempts=30
    local attempt=1
    print_info "Waiting for LocalStack to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if aws --endpoint-url="$AWS_ENDPOINT_URL" --region="$AWS_REGION" \
            sts get-caller-identity &>/dev/null; then
            print_success "LocalStack is ready!"
            return 0
        fi
        echo -ne "  ${DIM}Attempt $attempt/$max_attempts...${NC}\r"
        sleep 1
        ((attempt++))
    done
    print_error "LocalStack did not become ready in time"
    exit 1
}

# Start Postgres (and any other containers from calytics-be-admin compose)
start_postgres_container() {
    if docker ps --format '{{.Names}}' | grep -q "^${POSTGRES_CONTAINER}$"; then
        print_success "Postgres container '$POSTGRES_CONTAINER' is already running"
        return 0
    fi
    if docker ps -a --format '{{.Names}}' | grep -q "^${POSTGRES_CONTAINER}$"; then
        print_step "Starting Postgres container: $POSTGRES_CONTAINER"
        docker start "$POSTGRES_CONTAINER"
        print_success "Postgres container started"
        return 0
    fi
    if [ -f "$BE_ADMIN_DIR/docker-compose.local.yml" ]; then
        print_step "Creating and starting Postgres from calytics-be-admin compose..."
        (cd "$BE_ADMIN_DIR" && docker compose -f docker-compose.local.yml up -d db)
        print_success "Postgres container started ($POSTGRES_CONTAINER)"
        return 0
    fi
    print_warn "Postgres container '$POSTGRES_CONTAINER' not found and $BE_ADMIN_DIR/docker-compose.local.yml not found."
    print_info "Start Postgres manually: cd calytics-be-admin && docker compose -f docker-compose.local.yml up -d db"
}

# =============================================================================
# Main
# =============================================================================

print_banner
print_config

print_section "1" "Starting LocalStack"
start_localstack

print_section "2" "Seeding LocalStack SES (for local email)"
if [ -f "$SCRIPT_DIR/seed-localstack-ses.sh" ]; then
    print_step "Verifying SES identity (local@calytics.local) for calytics-a2a mandate emails..."
    (cd "$SCRIPT_DIR" && bash seed-localstack-ses.sh) || print_warn "SES seed failed (non-fatal); emails will still be written to .tmp/emails/"
else
    print_warn "scripts/seed-localstack-ses.sh not found; skip if not using calytics-a2a locally"
fi

print_section "3" "Starting Docker containers (Postgres, etc.)"
start_postgres_container

if docker ps --format '{{.Names}}' | grep -q "^${POSTGRES_CONTAINER}$"; then
    print_info "Waiting 2s for Postgres to accept connections..."
    sleep 2
fi

echo -e "\n${MAGENTA}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}${BOLD}║   ${GREEN}✅ Infrastructure prep complete${NC}${MAGENTA}${BOLD}                                    ║${NC}"
echo -e "${MAGENTA}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "\n  ${GREEN}✓${NC} LocalStack running at $AWS_ENDPOINT_URL (SES available for local email)"
echo -e "  ${GREEN}✓${NC} Postgres container: $POSTGRES_CONTAINER"
echo -e "\n${DIM}Next: run local-start.sh or a product prep script (e.g. local-start-a2a.sh).${NC}\n"
