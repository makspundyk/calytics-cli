#!/bin/bash

# =============================================================================
# Nuke Local Development Environment
#
# Kills all running processes, removes all Calytics Docker containers,
# deletes volumes (LocalStack data + Postgres data), and removes images.
# After this you get a completely clean slate.
#
# Usage:
#   ./local-nuke.sh
#   ./local-nuke.sh --keep-images   # skip image removal
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

print_step()    { echo -e "${CYAN}▸${NC}  $1"; }
print_success() { echo -e "${GREEN}✓${NC}  $1"; }
print_warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }

KEEP_IMAGES=false
if [ "${1:-}" = "--keep-images" ]; then
    KEEP_IMAGES=true
fi

CONTAINERS=("localstack_main" "calytics_postgres")
VOLUMES=("localstack_data" "calytics-be-admin_calytics_pg_data")
IMAGES=("localstack/localstack:3.8" "postgres:16-alpine")

echo -e "${RED}${BOLD}Nuking local development environment...${NC}\n"

# 1. Kill processes on known ports
for port in 9000 5000 4566; do
    if lsof -ti:$port &>/dev/null; then
        print_step "Killing process on port $port..."
        lsof -ti:$port | xargs kill -9 2>/dev/null || true
        print_success "Port $port freed"
    fi
done

# 2. Stop and remove containers
for name in "${CONTAINERS[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        print_step "Removing container $name..."
        docker rm -f "$name" 2>/dev/null || true
        print_success "$name removed"
    else
        print_warn "$name not found — skipping"
    fi
done

# 3. Remove volumes
for vol in "${VOLUMES[@]}"; do
    if docker volume ls -q | grep -q "^${vol}$"; then
        print_step "Removing volume $vol..."
        docker volume rm "$vol" 2>/dev/null || true
        print_success "$vol removed"
    else
        print_warn "Volume $vol not found — skipping"
    fi
done

# 4. Remove images (unless --keep-images)
if [ "$KEEP_IMAGES" = false ]; then
    for img in "${IMAGES[@]}"; do
        if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${img}$"; then
            print_step "Removing image $img..."
            docker rmi "$img" 2>/dev/null || true
            print_success "$img removed"
        else
            print_warn "Image $img not found — skipping"
        fi
    done
else
    print_warn "Keeping images (--keep-images flag)"
fi

echo -e "\n${GREEN}${BOLD}Clean slate. Run local-start.sh to rebuild everything.${NC}"
