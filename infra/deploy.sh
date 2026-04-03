#!/bin/bash
set -euo pipefail

# =============================================================================
# Calytics Local Deploy
#
# One-command local environment that mirrors AWS via Terraform + LocalStack.
#
# Presets (shorthand):
#   ./local-deploy.sh debit-guard        # BE + BE-admin only
#   ./local-deploy.sh a2a                # A2A + BE-admin only
#   ./local-deploy.sh full               # Everything
#
# Flags:
#   ./local-deploy.sh --env=sandbox                      # Sandbox naming
#   ./local-deploy.sh --skip=a2a,risk-scoring            # Skip services
#   ./local-deploy.sh --infra-only                       # Infrastructure only
#   ./local-deploy.sh --terraform-mode                   # Deploy Lambdas to LS
#   ./local-deploy.sh --destroy                          # Tear down everything
#
# Restart a single service:
#   ./local-deploy.sh restart be         # Restart calytics-be (port 3333)
#   ./local-deploy.sh restart a2a        # Restart calytics-a2a (port 3000)
#   ./local-deploy.sh restart risk       # Restart calytics-risk-scoring
#   ./local-deploy.sh restart be-admin   # Restart be-admin container
#   ./local-deploy.sh restart fe         # Restart fe container
#   ./local-deploy.sh restart docs       # Restart docs container
#
# Infrastructure is auto-detected — if LocalStack + Postgres are already
# running, Phases 1-3 are skipped automatically.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ── Defaults ─────────────────────────────────────────────────────
ENV="development"
SKIP=""
INFRA_ONLY=false
SERVICES_ONLY=false
TERRAFORM_MODE=false
DESTROY=false
BUILD=false
RESTART=""

# ── Parse flags ──────────────────────────────────────────────────
for arg in "$@"; do
  # Capture the service name after "restart"
  if [ "$RESTART" = "__next__" ]; then
    RESTART="$arg"
    continue
  fi
  case $arg in
    # Presets
    debit-guard|dg)   SKIP="a2a,risk-scoring,fe,docs" ;;
    a2a)              SKIP="be,risk-scoring,fe,docs" ;;
    full)             SKIP="" ;;
    backend)          SKIP="fe,docs" ;;
    admin|be-admin)   SKIP="be,a2a,risk-scoring,docs" ;;
    fe|frontend)      SKIP="be,a2a,risk-scoring,docs" ;;
    docs)             SKIP="be,a2a,risk-scoring,fe,be-admin" ;;
    # Flags
    --env=*)          ENV="${arg#*=}" ;;
    --skip=*)         SKIP="${arg#*=}" ;;
    --infra-only)     INFRA_ONLY=true ;;
    --services-only)  SERVICES_ONLY=true ;;
    --terraform-mode) TERRAFORM_MODE=true ;;
    --dev-mode)       TERRAFORM_MODE=false ;;
    --destroy)        DESTROY=true ;;
    --build)          BUILD=true ;;
    restart)          RESTART="__next__" ;;
    --help|-h)
      sed -n '3,/^# =====/p' "$0" | head -n -1 | sed 's/^# \?//'
      echo ""
      echo "Presets:"
      echo "  debit-guard, dg   BE + BE-admin (skips a2a, risk-scoring, fe, docs)"
      echo "  a2a               A2A + BE-admin (skips be, risk-scoring, fe, docs)"
      echo "  admin, be-admin   BE-admin + FE (skips be, a2a, risk-scoring, docs)"
      echo "  fe, frontend      BE-admin + FE (same as admin)"
      echo "  backend           All backends (skips fe, docs)"
      echo "  docs              API docs only (skips everything else)"
      echo "  full              Everything (default)"
      echo ""
      echo "Restart a single service:"
      echo "  restart be          Restart calytics-be (port 3333)"
      echo "  restart a2a         Restart calytics-a2a (port 3000)"
      echo "  restart risk        Restart calytics-risk-scoring"
      echo "  restart be-admin    Restart be-admin Docker container"
      echo "  restart fe          Restart fe Docker container"
      echo "  restart docs        Restart docs Docker container"
      exit 0 ;;
    *) echo "Unknown flag: $arg (try --help)"; exit 1 ;;
  esac
done

# Guard: restart was specified without a service name
if [ "$RESTART" = "__next__" ]; then
  echo "Usage: $0 restart <service> (try --help)"; exit 1
fi

# ── Colors ───────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
phase() { echo -e "\n${MAGENTA}${BOLD}══ $* ══${NC}\n"; }

should_skip() { echo ",$SKIP," | grep -qi ",$1,"; }

# ── Auto-detect running infrastructure ───────────────────────────
infra_is_running() {
  # Check LocalStack is healthy
  curl -sf http://localhost:4566/_localstack/health 2>/dev/null | grep -q '"dynamodb"' || return 1
  # Check Postgres is healthy
  docker exec calytics_postgres pg_isready -U postgres -d calytics-admin -q 2>/dev/null || return 1
  # Check Terraform state exists (resources were created)
  [ -f "$SCRIPT_DIR/terraform/local/terraform.tfstate" ] || return 1
  # Check SQS queues actually exist (catches container recreates that wipe state)
  aws --endpoint-url=http://localhost:4566 sqs get-queue-url \
    --queue-name "calytics-be-local-data-enrichment.fifo" \
    --region eu-central-1 &>/dev/null || return 1
  # Check PG has tables (migrations ran)
  docker exec calytics_postgres psql -U postgres -d calytics-admin -tAc \
    "SELECT count(*) FROM pg_tables WHERE schemaname='public';" 2>/dev/null | grep -q '^[1-9]' || return 1
  # Check seed data exists (main client)
  docker exec calytics_postgres psql -U postgres -d calytics-admin -tAc \
    "SELECT count(*) FROM clients;" 2>/dev/null | grep -q '^[1-9]' || return 1
  # Check secrets persist (Secrets Manager state is lost on LocalStack restart)
  aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
    --secret-id "calytics-be-admin/api-key-encryption" \
    --region eu-central-1 &>/dev/null || return 1
  return 0
}

if [ "$SERVICES_ONLY" = false ] && [ "$INFRA_ONLY" = false ] && [ "$DESTROY" = false ]; then
  if infra_is_running; then
    ok "Infrastructure already running — skipping Phases 1-3 (use --destroy to reset)"
    SERVICES_ONLY=true
  else
    # Partial infra detected — will run full setup to repair
    if docker ps --format '{{.Names}}' | grep -q 'localstack_main\|calytics_postgres'; then
      warn "Infrastructure partially running — will re-run setup to repair"
    fi
  fi
fi

# ── Destroy mode ─────────────────────────────────────────────────
if [ "$DESTROY" = true ]; then
  phase "Destroying local environment"

  info "Stopping Docker containers..."
  docker compose -f "$SCRIPT_DIR/calytics-cli/infra/docker-compose.yml" --env-file "$SCRIPT_DIR/.env" --profile app --profile docs down -v 2>/dev/null || true

  if [ -d "$SCRIPT_DIR/terraform/local/.terraform" ]; then
    info "Destroying Terraform resources..."
    (cd "$SCRIPT_DIR/terraform/local" && terraform destroy -var-file="env/${ENV}.tfvars" -auto-approve 2>/dev/null) || true
  fi

  for port in 9000 5000 3333 3000 4566; do
    lsof -ti:$port 2>/dev/null | xargs kill -9 2>/dev/null || true
  done

  ok "Environment destroyed"
  exit 0
fi

# ── Restart mode ─────────────────────────────────────────────────
if [ -n "$RESTART" ]; then
  case "$RESTART" in
    be|debit-guard|dg)
      phase "Restarting calytics-be"
      lsof -ti:3333 -ti:3334 2>/dev/null | xargs kill -9 2>/dev/null || true
      sleep 1
      info "Starting calytics-be (serverless-offline, port 3333)..."
      (cd "$SCRIPT_DIR/calytics-be" && npm run offline:local > /tmp/calytics-be.log 2>&1 &)
      for i in $(seq 1 30); do
        if grep -q "Server ready" /tmp/calytics-be.log 2>/dev/null; then ok "calytics-be ready on :3333"; break; fi
        [ "$i" -eq 30 ] && warn "calytics-be may still be starting — check: tail -f /tmp/calytics-be.log"
        sleep 1
      done
      ;;
    a2a)
      phase "Restarting calytics-a2a"
      lsof -ti:3000 2>/dev/null | xargs kill -9 2>/dev/null || true
      sleep 1
      info "Starting calytics-a2a (serverless-offline, port 3000)..."
      (cd "$SCRIPT_DIR/calytics-a2a" && npm run offline:local > /tmp/calytics-a2a.log 2>&1 &)
      for i in $(seq 1 30); do
        if grep -q "Server ready" /tmp/calytics-a2a.log 2>/dev/null; then ok "calytics-a2a ready on :3000"; break; fi
        [ "$i" -eq 30 ] && warn "calytics-a2a may still be starting — check: tail -f /tmp/calytics-a2a.log"
        sleep 1
      done
      ;;
    risk|risk-scoring)
      phase "Restarting calytics-risk-scoring"
      # risk-scoring doesn't bind a fixed port — find its PID from the log
      pgrep -f "calytics-risk-scoring.*stream:dev" 2>/dev/null | xargs kill -9 2>/dev/null || true
      sleep 1
      info "Starting calytics-risk-scoring (stream subscriber)..."
      (cd "$SCRIPT_DIR/calytics-risk-scoring" && npm run stream:dev > /tmp/calytics-risk-scoring.log 2>&1 &)
      ok "calytics-risk-scoring started — check: tail -f /tmp/calytics-risk-scoring.log"
      ;;
    be-admin|admin)
      phase "Restarting be-admin"
      docker restart calytics_be_admin 2>/dev/null && ok "be-admin restarted" || fail "be-admin container not found"
      ;;
    fe|frontend)
      phase "Restarting fe"
      docker restart calytics_fe 2>/dev/null && ok "fe restarted" || fail "fe container not found"
      ;;
    docs)
      phase "Restarting docs"
      docker restart calytics_docs 2>/dev/null && ok "docs restarted" || fail "docs container not found"
      ;;
    *)
      fail "Unknown service: $RESTART (try: be, a2a, risk, be-admin, fe, docs)"
      ;;
  esac
  exit 0
fi

# ══════════════════════════════════════════════════════════════════
# Phase 1: Infrastructure
# ══════════════════════════════════════════════════════════════════
if [ "$SERVICES_ONLY" = false ]; then
  phase "Phase 1: Infrastructure (LocalStack + Postgres)"

  # Remove orphan containers that conflict with compose-managed names
  for name in localstack_main calytics_postgres; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
      info "Removing existing container $name..."
      docker rm -f "$name" 2>/dev/null || true
    fi
  done

  info "Starting LocalStack and Postgres..."
  docker compose -f "$SCRIPT_DIR/calytics-cli/infra/docker-compose.yml" --env-file "$SCRIPT_DIR/.env" up -d localstack postgres

  info "Waiting for LocalStack..."
  for i in $(seq 1 30); do
    if curl -sf http://localhost:4566/_localstack/health | grep -q '"dynamodb"'; then
      ok "LocalStack is healthy"
      break
    fi
    [ "$i" -eq 30 ] && fail "LocalStack did not start within 30s"
    sleep 1
  done

  info "Waiting for Postgres..."
  for i in $(seq 1 30); do
    if docker exec calytics_postgres pg_isready -U postgres -d calytics-admin -q 2>/dev/null; then
      ok "Postgres is healthy"
      break
    fi
    [ "$i" -eq 30 ] && fail "Postgres did not start within 30s"
    sleep 1
  done

# ══════════════════════════════════════════════════════════════════
# Phase 2: Terraform
# ══════════════════════════════════════════════════════════════════
  phase "Phase 2: Terraform (AWS resources -> LocalStack)"

  TF_DIR="$SCRIPT_DIR/terraform/local"
  TF_VARS="-var-file=env/${ENV}.tfvars"

  # Apply skip flags
  if should_skip "a2a"; then         TF_VARS="$TF_VARS -var=enable_a2a=false"; fi
  if should_skip "risk-scoring"; then TF_VARS="$TF_VARS -var=enable_risk_scoring=false"; fi
  if should_skip "be"; then          TF_VARS="$TF_VARS -var=enable_be=false"; fi
  if [ "$TERRAFORM_MODE" = true ]; then TF_VARS="$TF_VARS -var=enable_lambdas=true"; fi

  info "Running terraform init..."
  (cd "$TF_DIR" && terraform init -input=false -no-color) || fail "terraform init failed"

  info "Running terraform apply (env=$ENV)..."
  if ! (cd "$TF_DIR" && terraform apply $TF_VARS -auto-approve -no-color); then
    warn "Terraform apply failed — retrying once..."
    sleep 3
    (cd "$TF_DIR" && terraform apply $TF_VARS -auto-approve -no-color) || fail "terraform apply failed on retry"
  fi

  ok "Terraform resources created in LocalStack"

# ══════════════════════════════════════════════════════════════════
# Phase 3: Database & Seeding
# ══════════════════════════════════════════════════════════════════
  phase "Phase 3: Database & Seeding"

  ADMIN_DIR="$SCRIPT_DIR/calytics-be-admin"
  cd "$ADMIN_DIR"

  info "Building calytics-be-admin..."
  # Clean dist/ which may be owned by root from Docker container runs
  if [ -d "$ADMIN_DIR/dist" ]; then
    sudo rm -rf "$ADMIN_DIR/dist" 2>/dev/null || rm -rf "$ADMIN_DIR/dist"
  fi
  npm run build 2>&1 | tail -3
  ok "Build complete"

  info "Running PostgreSQL migrations..."
  for i in $(seq 1 100); do
    OUTPUT=$(npm run --silent postgres:migration:run 2>&1)
    echo "$OUTPUT"
    if echo "$OUTPUT" | grep -q "No migrations are pending"; then
      ok "All PostgreSQL migrations applied"
      break
    fi
    if echo "$OUTPUT" | grep -qi "error"; then
      fail "Migration failed — check output above"
    fi
  done

  info "Seeding admins..."
  npm run seed:admins 2>&1 | tail -3
  ok "Admins seeded"

  info "Seeding clients..."
  npm run seed:clients 2>&1 | tail -3
  ok "Clients seeded"

  # Run additional seed scripts if they exist
  for seed_script in \
    "$SCRIPT_DIR/calytics-cli/seeders/webhooks.sh" \
    "$SCRIPT_DIR/calytics-cli/seeders/plans.sh" \
    "$SCRIPT_DIR/calytics-cli/seeders/api-keys.sh"; do
    if [ -f "$seed_script" ]; then
      info "Running $(basename "$seed_script")..."
      bash "$seed_script" 2>&1 | tail -5
      ok "$(basename "$seed_script") done"
    fi
  done

  cd "$SCRIPT_DIR"
fi

# ══════════════════════════════════════════════════════════════════
# Phase 3.5: Sync & build shared modules
#
# For each git repo in calytics-shared-modules/:
#   1. Fetch remote changes
#   2. Auto-switch to main if current branch has no local work
#      (forgotten feature branch that was already merged)
#   3. Build only if dist/ is missing or stale vs source
# ══════════════════════════════════════════════════════════════════
SHARED_MODULES_DIR="$SCRIPT_DIR/calytics-shared-modules"
if [ -d "$SHARED_MODULES_DIR" ]; then
  phase "Phase 3.5: Sync & build shared modules"

  SHIM_REBUILD_NEEDED=false

  for mod_dir in "$SHARED_MODULES_DIR"/*/; do
    [ ! -d "$mod_dir/.git" ] && continue
    mod_name=$(basename "$mod_dir")

    # Skip if no package.json or no build script
    if [ ! -f "$mod_dir/package.json" ]; then
      continue
    fi
    if ! grep -q '"build"' "$mod_dir/package.json" 2>/dev/null; then
      warn "$mod_name — no build script, skipping"
      continue
    fi

    info "$mod_name — syncing..."

    # ── 1. Fetch remote ──────────────────────────────────────────
    (cd "$mod_dir" && git fetch origin --quiet 2>/dev/null) || true

    # ── 2. Branch decision ───────────────────────────────────────
    current_branch=$(cd "$mod_dir" && git branch --show-current 2>/dev/null)
    if [ -n "$current_branch" ] && [ "$current_branch" != "main" ]; then
      # Check for local work: uncommitted changes OR commits ahead of remote
      has_uncommitted=$(cd "$mod_dir" && git status --porcelain 2>/dev/null)
      has_local_commits=$(cd "$mod_dir" && git log "@{u}..HEAD" --oneline 2>/dev/null)

      if [ -z "$has_uncommitted" ] && [ -z "$has_local_commits" ]; then
        # No local work — this branch was likely forgotten after merge
        warn "$mod_name — branch '$current_branch' has no local work, switching to main"
        (cd "$mod_dir" && git checkout main --quiet 2>/dev/null && git pull --ff-only origin main --quiet 2>/dev/null) || true
        current_branch="main"
      else
        ok "$mod_name — staying on '$current_branch' (has local work)"
      fi
    elif [ -n "$current_branch" ] && [ "$current_branch" = "main" ]; then
      # On main — pull latest
      (cd "$mod_dir" && git pull --ff-only origin main --quiet 2>/dev/null) || true
    fi

    # ── 3. Build decision ────────────────────────────────────────
    needs_build=false

    # Find the dist/ directory — either root-level or inside packages/*/ (workspace monorepo)
    dist_dir="$mod_dir/dist"
    if [ ! -d "$dist_dir" ] && [ -d "$mod_dir/packages" ]; then
      dist_dir=$(find "$mod_dir/packages" -maxdepth 2 -name "dist" -type d | head -1)
    fi

    if [ -z "$dist_dir" ] || [ ! -d "$dist_dir" ]; then
      needs_build=true
      info "$mod_name — no dist/, needs build"
    else
      # Check if any source file is newer than the dist/ build marker
      build_marker="$dist_dir/index.js"
      [ ! -f "$build_marker" ] && build_marker="$dist_dir/index.d.ts"
      [ ! -f "$build_marker" ] && build_marker=$(find "$dist_dir" -name "*.js" -type f | head -1)

      if [ -z "$build_marker" ]; then
        needs_build=true
        info "$mod_name — dist/ is empty, needs build"
      else
        # Find any source file newer than the build marker (check both root src/ and packages/*/src/)
        newer_src=$(find "$mod_dir/src" "$mod_dir/packages" -name "*.ts" -not -name "*.d.ts" -newer "$build_marker" 2>/dev/null | head -1)
        if [ -n "$newer_src" ]; then
          needs_build=true
          info "$mod_name — source changed since last build ($(basename "$newer_src"))"
        fi
      fi
    fi

    # ── 4. Build if needed ───────────────────────────────────────
    if [ "$needs_build" = true ]; then
      info "$mod_name — building..."
      if (cd "$mod_dir" && npm install --silent 2>/dev/null && npm run build 2>&1 | tail -5); then
        ok "$mod_name — built successfully"
        SHIM_REBUILD_NEEDED=true
      else
        warn "$mod_name — build failed (non-fatal)"
      fi
    else
      ok "$mod_name — dist/ is up to date"
    fi
  done
fi

# ══════════════════════════════════════════════════════════════════
# Phase 3.6: Build alias shims + patch pino for serverless-offline
# ══════════════════════════════════════════════════════════════════
if ! should_skip "be"; then
  BE_SHIM_SCRIPT="$SCRIPT_DIR/calytics-be/scripts/build-local-alias-shims.sh"
  if [ -f "$BE_SHIM_SCRIPT" ]; then
    shims_needed=false

    # Rebuild if shims don't exist
    if [ ! -d "$SCRIPT_DIR/calytics-be/node_modules/@infrastructure" ]; then
      shims_needed=true
    fi

    # Rebuild if pino is unpatched (e.g. after npm install)
    if [ -f "$SCRIPT_DIR/calytics-be/node_modules/pino/lib/symbols.js" ] && \
       grep -q "Symbol('pino\." "$SCRIPT_DIR/calytics-be/node_modules/pino/lib/symbols.js" 2>/dev/null; then
      shims_needed=true
    fi

    # Rebuild if shared modules were rebuilt
    if [ "${SHIM_REBUILD_NEEDED:-false}" = true ]; then
      shims_needed=true
    fi

    # Rebuild if any source is newer than shims
    if [ "$shims_needed" = false ] && [ -d "$SCRIPT_DIR/calytics-be/node_modules/@infrastructure" ]; then
      shim_marker="$SCRIPT_DIR/calytics-be/node_modules/@infrastructure/package.json"
      for src_dir in infrastructure shared core domains; do
        if [ -n "$(find "$SCRIPT_DIR/calytics-be/src/$src_dir" -name '*.ts' -newer "$shim_marker" 2>/dev/null | head -1)" ]; then
          shims_needed=true
          break
        fi
      done
    fi

    if [ "$shims_needed" = true ]; then
      info "Building alias shims + patching pino for calytics-be..."
      bash "$BE_SHIM_SCRIPT" 2>&1 | tail -5
    else
      ok "Alias shims up to date"
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════
# Phase 4: Application Services
# ══════════════════════════════════════════════════════════════════
if [ "$INFRA_ONLY" = false ]; then
  phase "Phase 4: Application Services"

  # Kill leftover processes on app ports
  for port in 9000 5000 3333 3000; do
    lsof -ti:$port 2>/dev/null | xargs kill -9 2>/dev/null || true
  done

  # Container services via docker compose profiles
  PROFILES=""
  if ! should_skip "be-admin" && ! should_skip "fe"; then
    PROFILES="app"
  fi
  if ! should_skip "docs"; then
    PROFILES="${PROFILES:+$PROFILES }docs"
  fi

  if [ -n "$PROFILES" ]; then
    for profile in $PROFILES; do
      info "Starting Docker profile: $profile..."
      docker compose -f "$SCRIPT_DIR/calytics-cli/infra/docker-compose.yml" --env-file "$SCRIPT_DIR/.env" --profile "$profile" up -d
    done
  fi

  # Lambda services (dev mode = serverless-offline)
  if [ "$TERRAFORM_MODE" = false ]; then
    if ! should_skip "be"; then
      info "Starting calytics-be (serverless-offline, port 3333)..."
      (cd "$SCRIPT_DIR/calytics-be" && npm run offline:local > /tmp/calytics-be.log 2>&1 &)
    fi

    if ! should_skip "a2a"; then
      info "Starting calytics-a2a (serverless-offline, port 3000)..."
      (cd "$SCRIPT_DIR/calytics-a2a" && npm run offline:local > /tmp/calytics-a2a.log 2>&1 &)
    fi

    if ! should_skip "risk-scoring"; then
      info "Starting calytics-risk-scoring (stream subscriber)..."
      (cd "$SCRIPT_DIR/calytics-risk-scoring" && npm run stream:dev > /tmp/calytics-risk-scoring.log 2>&1 &)
    fi
  fi

  ok "All services started"
fi

# ══════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════
# ── Determine display mode ────────────────────────────────────────
if [ "$DESTROY" = true ]; then
  DISPLAY_MODE="destroy"
elif [ "$INFRA_ONLY" = true ]; then
  DISPLAY_MODE="infra-only"
elif [ "$SERVICES_ONLY" = true ]; then
  DISPLAY_MODE="services-only"
elif [ "$TERRAFORM_MODE" = true ]; then
  DISPLAY_MODE="terraform"
else
  DISPLAY_MODE="dev"
fi

echo ""
if [ "$DISPLAY_MODE" = "destroy" ]; then
  echo -e "${GREEN}${BOLD}+----------------------------------------------+${NC}"
  echo -e "${GREEN}${BOLD}|  Local environment destroyed                 |${NC}"
  echo -e "${GREEN}${BOLD}+----------------------------------------------+${NC}"
  echo ""
else
  echo -e "${GREEN}${BOLD}+----------------------------------------------+${NC}"
  echo -e "${GREEN}${BOLD}|  Local environment is ready!                 |${NC}"
  echo -e "${GREEN}${BOLD}+----------------------------------------------+${NC}"
  echo ""
  echo -e "  Environment:    ${CYAN}$ENV${NC}"
  echo -e "  Mode:           ${CYAN}$DISPLAY_MODE${NC}"
  [ -n "$SKIP" ] && echo -e "  Skipped:        ${YELLOW}$SKIP${NC}"

  # Infrastructure endpoints (not shown for --services-only)
  if [ "$SERVICES_ONLY" = false ]; then
    echo ""
    echo -e "  ${BOLD}Infrastructure:${NC}"
    echo -e "    LocalStack:     ${CYAN}http://localhost:4566${NC}"
    echo -e "    PostgreSQL:     ${CYAN}localhost:5432${NC}"
  fi

  # Service endpoints (not shown for --infra-only)
  if [ "$INFRA_ONLY" = false ]; then
    # Detect LAN IP for FE access from other devices
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    echo ""
    echo -e "  ${BOLD}Services:${NC}"
    if ! should_skip "fe"; then
      echo -e "    Frontend:       ${CYAN}http://localhost:5000${NC}"
      [ "$LOCAL_IP" != "localhost" ] && \
        echo -e "    Frontend (LAN): ${CYAN}http://${LOCAL_IP}:5000${NC}"
    fi
    should_skip "be-admin"     || echo -e "    Admin API:      ${CYAN}http://localhost:9000${NC}"
    should_skip "be"           || echo -e "    Banking API:    ${CYAN}http://localhost:3333${NC}"
    should_skip "a2a"          || echo -e "    A2A API:        ${CYAN}http://localhost:3000${NC}"
    should_skip "docs"         || echo -e "    API Docs:       ${CYAN}http://localhost:8080${NC}"
  fi

  echo ""
  echo -e "  ${BOLD}Credentials:${NC}"
  echo -e "    Client:  main.client@gmail.com / ClientSecret123!"
  echo -e "    Admin:   app.admin@gmail.com / AdminSecret123!"

  # Logs (only for dev mode with serverless-offline; terraform-mode runs inside LocalStack)
  if [ "$INFRA_ONLY" = false ] && [ "$TERRAFORM_MODE" = false ]; then
    echo ""
    echo -e "  ${BOLD}Logs:${NC}"
    should_skip "be"           || echo -e "    calytics-be:           ${CYAN}tail -f /tmp/calytics-be.log${NC}"
    should_skip "a2a"          || echo -e "    calytics-a2a:          ${CYAN}tail -f /tmp/calytics-a2a.log${NC}"
    should_skip "risk-scoring" || echo -e "    calytics-risk-scoring: ${CYAN}tail -f /tmp/calytics-risk-scoring.log${NC}"
  fi
fi
echo ""
