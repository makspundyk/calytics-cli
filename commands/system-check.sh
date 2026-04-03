#!/bin/bash
# cal system-check
# Full diagnostic report: tools, services, env files, consistency, auth tokens.
# Run this before `cal deploy` to catch issues early.

PASS=0; WARN=0; FAIL_COUNT=0

check_pass() { ((PASS++)); echo -e "  ${GREEN}PASS${NC}  $*"; }
check_warn() { ((WARN++)); echo -e "  ${YELLOW}WARN${NC}  $*"; }
check_fail() { ((FAIL_COUNT++)); echo -e "  ${RED}FAIL${NC}  $*"; }

has() { command -v "$1" &>/dev/null; }

echo ""
echo -e "${BOLD}  ╔═══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║         Calytics System Check             ║${NC}"
echo -e "${BOLD}  ╚═══════════════════════════════════════════╝${NC}"

# ══════════════════════════════════════════════════════════════════
# 1. Required CLI tools
# ══════════════════════════════════════════════════════════════════
phase "1. CLI Tools"

declare -A TOOLS=(
  [git]="Source control"
  [node]="Node.js runtime"
  [npm]="Package manager"
  [docker]="Container runtime"
  [aws]="AWS CLI"
  [terraform]="Infrastructure as code"
  [serverless]="Serverless Framework"
  [jq]="JSON processor"
  [curl]="HTTP client"
  [lsof]="Port checker"
  [openssl]="Encryption"
  [zip]="Archive tool"
  [psql]="PostgreSQL client"
)

for tool in git node npm docker aws terraform serverless jq curl lsof openssl zip psql; do
  desc="${TOOLS[$tool]}"
  if has "$tool"; then
    version=$("$tool" --version 2>&1 | head -1 | grep -oP '[\d]+\.[\d]+\.?[\d]*' | head -1)
    check_pass "$tool ${DIM}($desc) v$version${NC}"
  else
    check_fail "$tool — $desc not installed"
  fi
done

# Node version check
if has node; then
  node_major=$(node -v | grep -oP '\d+' | head -1)
  if [ "$node_major" -ge 22 ]; then
    check_pass "Node.js >= 22 ${DIM}($(node -v))${NC}"
  else
    check_fail "Node.js $(node -v) — requires >= 22"
  fi
fi

# Optional tools
for tool in ngrok claude pgrep; do
  if has "$tool"; then
    check_pass "$tool ${DIM}(optional)${NC}"
  else
    check_warn "$tool not installed (optional)"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 2. Docker
# ══════════════════════════════════════════════════════════════════
phase "2. Docker"

if has docker; then
  if docker info &>/dev/null; then
    check_pass "Docker daemon running"
  else
    check_fail "Docker installed but daemon not running (start Docker Desktop or: sudo systemctl start docker)"
  fi

  if docker compose version &>/dev/null; then
    check_pass "Docker Compose plugin $(docker compose version --short 2>/dev/null)"
  else
    check_fail "Docker Compose plugin missing"
  fi

  # Check if user is in docker group
  if groups | grep -q docker; then
    check_pass "User in docker group"
  else
    check_warn "User not in docker group — may need sudo for docker commands"
  fi
fi

# ══════════════════════════════════════════════════════════════════
# 3. AWS / LocalStack auth
# ══════════════════════════════════════════════════════════════════
phase "3. AWS & LocalStack"

if has aws; then
  # Check LocalStack reachability
  if curl -sf http://localhost:${INFRA_LOCALSTACK_PORT}/_localstack/health &>/dev/null; then
    check_pass "LocalStack reachable on :${INFRA_LOCALSTACK_PORT}"

    # Check specific services (needs jq)
    if has jq; then
      health=$(curl -sf http://localhost:${INFRA_LOCALSTACK_PORT}/_localstack/health 2>/dev/null)
      for svc_name in dynamodb sqs s3 secretsmanager ses; do
        if echo "$health" | jq -r ".services.$svc_name" 2>/dev/null | grep -qi "available\|running"; then
          check_pass "LocalStack $svc_name ${DIM}available${NC}"
        else
          check_warn "LocalStack $svc_name not reported as available"
        fi
      done
    else
      check_warn "LocalStack service check skipped (jq not installed)"
    fi
  else
    check_warn "LocalStack not reachable (run: cal deploy)"
  fi

  # Check real AWS auth (for sync commands)
  if aws sts get-caller-identity --region eu-central-1 &>/dev/null; then
    aws_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    check_pass "AWS authenticated ${DIM}(account: $aws_account)${NC}"
  else
    check_warn "AWS not authenticated (sync commands won't work — run: aws configure)"
  fi
fi

# ngrok auth
if has ngrok; then
  if ngrok config check &>/dev/null 2>&1; then
    check_pass "ngrok auth token configured"
  else
    check_warn "ngrok auth token missing (run: ngrok config add-authtoken <token>)"
  fi
fi

# ══════════════════════════════════════════════════════════════════
# 4. Infrastructure state
# ══════════════════════════════════════════════════════════════════
phase "4. Infrastructure"

if container_is_running "$INFRA_LOCALSTACK_CONTAINER"; then
  check_pass "LocalStack container running"
else
  check_warn "LocalStack container not running"
fi

if container_is_running "$INFRA_POSTGRES_CONTAINER"; then
  check_pass "PostgreSQL container running"

  # Check DB connectivity
  if docker exec "$INFRA_POSTGRES_CONTAINER" pg_isready -U postgres -d calytics-admin -q &>/dev/null; then
    check_pass "PostgreSQL accepting connections"

    # Check tables exist
    table_count=$(docker exec "$INFRA_POSTGRES_CONTAINER" psql -U postgres -d calytics-admin -tAc "SELECT count(*) FROM pg_tables WHERE schemaname='public';" 2>/dev/null)
    if [ "${table_count:-0}" -gt 0 ]; then
      check_pass "PostgreSQL has $table_count tables"
    else
      check_warn "PostgreSQL has no tables (run: cal migrate run --all)"
    fi
  else
    check_fail "PostgreSQL not accepting connections"
  fi
else
  check_warn "PostgreSQL container not running"
fi

# Terraform state
TF_DIR="$CAL_PROJECT/terraform/local"
if [ -f "$TF_DIR/terraform.tfstate" ]; then
  check_pass "Terraform state exists"
else
  check_warn "No Terraform state (run: cal deploy)"
fi

# ══════════════════════════════════════════════════════════════════
# 5. Project root env files
# ══════════════════════════════════════════════════════════════════
phase "5. Environment Files (project root)"

if [ -f "$CAL_PROJECT/.env" ]; then
  check_pass ".env exists"
  # Check if WSL IP is still valid
  env_ip=$(grep -oP 'http://\K[^:]+' "$CAL_PROJECT/.env" | head -1)
  current_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  if [ "$env_ip" = "$current_ip" ]; then
    check_pass ".env WSL IP matches current ($current_ip)"
  else
    check_warn ".env has IP $env_ip but current WSL IP is $current_ip (update .env)"
  fi
else
  check_fail ".env missing (run: cal install)"
fi

if [ -f "$CAL_PROJECT/.env.local" ]; then
  check_pass ".env.local exists"
else
  check_fail ".env.local missing (run: cal install)"
fi

# ══════════════════════════════════════════════════════════════════
# 6. Service .env files
# ══════════════════════════════════════════════════════════════════
phase "6. Service .env Files"

for svc in be a2a admin rs fe; do
  svc_dir="$(svc_path "$svc")"
  label="${SVC_LABEL[$svc]}"

  if [ ! -d "$svc_dir" ]; then
    check_warn "$label directory not found"
    continue
  fi

  env_file="$svc_dir/.env"
  env_example="$svc_dir/.env.example"
  env_template="$svc_dir/.env.template"

  if [ -f "$env_file" ]; then
    check_pass "$label .env exists"
  elif [ -f "$env_example" ] || [ -f "$env_template" ]; then
    check_fail "$label .env missing (template exists — copy it)"
  else
    check_warn "$label no .env found"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 7. Cross-service consistency
# ══════════════════════════════════════════════════════════════════
phase "7. Cross-Service Consistency"

be_env="$(svc_path be)/.env"
admin_env="$(svc_path admin)/.env"
a2a_env="$(svc_path a2a)/.env"
rs_env="$(svc_path rs)/.env"

# Helper: get value of a key from an env file
env_val() { grep "^${2}=" "$1" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '\r'; }

# AWS_ENVIRONMENT consistency
if [ -f "$be_env" ]; then
  be_aws_env=$(env_val "$be_env" "AWS_ENVIRONMENT")
  if [ "$be_aws_env" != "local" ] && [ -n "$be_aws_env" ]; then
    check_warn "calytics-be AWS_ENVIRONMENT=$be_aws_env (expected: local)"
  else
    check_pass "calytics-be AWS_ENVIRONMENT=local"
  fi
fi

# PostgreSQL consistency
if [ -f "$be_env" ] && [ -f "$admin_env" ]; then
  be_pg_host=$(env_val "$be_env" "PG_HOST")
  admin_pg_host=$(env_val "$admin_env" "POSTGRES_HOST")
  be_pg_db=$(env_val "$be_env" "PG_NAME")
  admin_pg_db=$(env_val "$admin_env" "POSTGRES_NAME")

  if [ "$be_pg_host" = "$admin_pg_host" ]; then
    check_pass "PostgreSQL host consistent ($be_pg_host)"
  else
    check_warn "PostgreSQL host mismatch: be=$be_pg_host admin=$admin_pg_host"
  fi

  if [ "$be_pg_db" = "$admin_pg_db" ]; then
    check_pass "PostgreSQL database name consistent ($be_pg_db)"
  else
    check_warn "PostgreSQL database mismatch: be=$be_pg_db admin=$admin_pg_db"
  fi
fi

# JWT secret consistency
if [ -f "$be_env" ] && [ -f "$admin_env" ]; then
  be_jwt=$(env_val "$be_env" "JWT_SECRET")
  admin_jwt=$(env_val "$admin_env" "JWT_SECRET")
  if [ -n "$be_jwt" ] && [ "$be_jwt" = "$admin_jwt" ]; then
    check_pass "JWT_SECRET matches between be and admin"
  elif [ -n "$be_jwt" ] && [ -n "$admin_jwt" ]; then
    check_fail "JWT_SECRET mismatch between be and admin"
  fi
fi

# Shared DynamoDB table consistency
if [ -f "$be_env" ] && [ -f "$admin_env" ]; then
  for table_var in VERIFICATIONS_TABLE_NAME TRANSACTIONS_TABLE_NAME VENDOR_DATA_TABLE_NAME TRANSACTION_CODE_TABLE_NAME AIS_SESSION_CONNECTIONS_TABLE_NAME; do
    be_val=$(env_val "$be_env" "$table_var")
    admin_val=$(env_val "$admin_env" "$table_var")
    if [ -n "$be_val" ] && [ -n "$admin_val" ]; then
      if [ "$be_val" = "$admin_val" ]; then
        check_pass "$table_var consistent ${DIM}($be_val)${NC}"
      else
        check_fail "$table_var mismatch: be=$be_val admin=$admin_val"
      fi
    fi
  done
fi

# Disputed transactions table (known issue: be vs risk-scoring may differ)
if [ -f "$be_env" ] && [ -f "$rs_env" ]; then
  be_disputed=$(env_val "$be_env" "DISPUTED_TRANSACTIONS_TABLE_NAME")
  rs_disputed=$(env_val "$rs_env" "DISPUTED_TRANSACTIONS_TABLE_NAME")
  if [ -n "$be_disputed" ] && [ -n "$rs_disputed" ]; then
    if [ "$be_disputed" = "$rs_disputed" ]; then
      check_pass "DISPUTED_TRANSACTIONS_TABLE_NAME consistent"
    else
      check_warn "DISPUTED_TRANSACTIONS_TABLE_NAME differs: be=$be_disputed rs=$rs_disputed"
    fi
  fi
fi

# SQS queue URL format consistency
if [ -f "$be_env" ] && [ -f "$admin_env" ]; then
  be_queue=$(env_val "$be_env" "DATA_ENRICHMENT_QUEUE_URL")
  admin_queue=$(env_val "$admin_env" "DATA_ENRICHMENT_QUEUE_URL")
  if [ -n "$be_queue" ] && [ -n "$admin_queue" ]; then
    if [ "$be_queue" = "$admin_queue" ]; then
      check_pass "DATA_ENRICHMENT_QUEUE_URL consistent (be/admin)"
    else
      check_warn "DATA_ENRICHMENT_QUEUE_URL differs between be and admin"
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════
# 8. Shared modules
# ══════════════════════════════════════════════════════════════════
phase "8. Shared Modules"

if [ -d "$SHARED_MODULES_DIR" ]; then
  for mod_dir in "$SHARED_MODULES_DIR"/*/; do
    [ ! -d "$mod_dir/.git" ] && continue
    mod_name=$(basename "$mod_dir")
    has_build=$(grep -q '"build"' "$mod_dir/package.json" 2>/dev/null && echo "yes" || echo "no")
    [ "$has_build" = "no" ] && continue

    # Check dist/ exists
    dist_dir="$mod_dir/dist"
    [ ! -d "$dist_dir" ] && [ -d "$mod_dir/packages" ] && dist_dir=$(find "$mod_dir/packages" -maxdepth 2 -name "dist" -type d | head -1)

    if [ -n "$dist_dir" ] && [ -d "$dist_dir" ]; then
      check_pass "$mod_name built (dist/ exists)"
    else
      check_fail "$mod_name not built (run: cal build shared)"
    fi

    # Check branch
    branch=$(cd "$mod_dir" && git branch --show-current 2>/dev/null)
    if [ "$branch" = "main" ]; then
      check_pass "$mod_name on main"
    else
      check_warn "$mod_name on branch '$branch' (not main)"
    fi
  done
else
  check_warn "calytics-shared-modules directory not found"
fi

# ══════════════════════════════════════════════════════════════════
# 9. calytics-be local dev readiness
# ══════════════════════════════════════════════════════════════════
phase "9. calytics-be Local Dev"

be_dir="$(svc_path be)"
if [ -d "$be_dir" ]; then
  # node_modules
  if [ -d "$be_dir/node_modules" ]; then
    check_pass "node_modules installed"
  else
    check_fail "node_modules missing (run: cd $(svc_path be) && npm install)"
  fi

  # Alias shims
  if [ -d "$be_dir/node_modules/@infrastructure" ]; then
    check_pass "Alias shims built"
  else
    check_warn "Alias shims missing (run: cal build shims)"
  fi

  # Pino patch
  pino_symbols="$be_dir/node_modules/pino/lib/symbols.js"
  if [ -f "$pino_symbols" ]; then
    if grep -q "Symbol('pino\." "$pino_symbols" 2>/dev/null; then
      check_warn "pino symbols NOT patched (run: cal build shims)"
    else
      check_pass "pino symbols patched (Symbol.for)"
    fi
  fi

  # @calytics symlinks
  for pkg in ais-connection payment-reconciliation; do
    link="$be_dir/node_modules/@calytics/$pkg"
    if [ -L "$link" ] && [ -e "$link" ]; then
      check_pass "@calytics/$pkg symlink valid"
    elif [ -L "$link" ]; then
      check_fail "@calytics/$pkg symlink broken (target missing)"
    else
      check_warn "@calytics/$pkg not linked"
    fi
  done
fi

# ══════════════════════════════════════════════════════════════════
# 10. Service ports
# ══════════════════════════════════════════════════════════════════
phase "10. Service Ports"

for svc in "${SVC_ALL_LIST[@]}"; do
  port="${SVC_PORT[$svc]}"
  label="${SVC_LABEL[$svc]}"
  [ "$port" -eq 0 ] && continue

  if port_is_busy "$port"; then
    check_pass ":$port $label ${DIM}(in use)${NC}"
  else
    dim "  ----  :$port $label (not running)"
  fi
done

# ══════════════════════════════════════════════════════════════════
# Report
# ══════════════════════════════════════════════════════════════════
echo ""
echo -e "  ┌─────────────────────────────────────┐"
echo -e "  │  ${GREEN}PASS: $PASS${NC}   ${YELLOW}WARN: $WARN${NC}   ${RED}FAIL: $FAIL_COUNT${NC}  │"
echo -e "  └─────────────────────────────────────┘"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo -e "  ${RED}Fix the FAIL items before running cal deploy.${NC}"
elif [ "$WARN" -gt 0 ]; then
  echo -e "  ${YELLOW}Warnings are non-blocking but worth reviewing.${NC}"
else
  echo -e "  ${GREEN}All checks passed. Ready to deploy.${NC}"
fi
echo ""
