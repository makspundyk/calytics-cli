#!/bin/bash
# Shared utility functions
# All names/config come from lib/names.sh (sourced via lib/services.sh).

# Derived paths (from CAL_ROOT and CAL_PROJECT, set by cal.sh)
COMPOSE_FILE="$CAL_ROOT/infra/docker-compose.yml"
COMPOSE_ENV="$CAL_PROJECT/.env"
SEEDERS_DIR="$CAL_ROOT/seeders"
TF_DIR="$CAL_ROOT/infra/terraform/local"

# Wrapper: docker compose with correct file, env, and project name
dc() {
  docker compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV" -p "$COMPOSE_PROJECT" "$@"
}

# Check if infrastructure is running
infra_is_running() {
  container_is_running "$INFRA_LOCALSTACK_CONTAINER" && container_is_running "$INFRA_POSTGRES_CONTAINER"
}

# Ensure infrastructure is running — start it if not
ensure_infra() {
  if infra_is_running; then
    return 0
  fi

  info "Infrastructure not running — starting..."
  docker start "$INFRA_LOCALSTACK_CONTAINER" 2>/dev/null || dc up -d localstack postgres 2>/dev/null
  docker start "$INFRA_POSTGRES_CONTAINER" 2>/dev/null || true

  # Wait for LocalStack
  for i in $(seq 1 30); do
    if curl -sf "http://localhost:${INFRA_LOCALSTACK_PORT}/_localstack/health" 2>/dev/null | grep -q '"dynamodb"'; then
      break
    fi
    [ "$i" -eq 30 ] && { warn "LocalStack may still be starting"; return 1; }
    sleep 1
  done
  ok "LocalStack ready"

  # Wait for Postgres
  for i in $(seq 1 15); do
    if docker exec "$INFRA_POSTGRES_CONTAINER" pg_isready -U postgres -d calytics-admin -q 2>/dev/null; then
      break
    fi
    sleep 1
  done
  ok "PostgreSQL ready"

  # Re-seed LocalStack resources that don't survive restarts
  LS="http://localhost:${INFRA_LOCALSTACK_PORT}"

  # SQS queues
  if ! aws --endpoint-url="$LS" sqs get-queue-url \
       --queue-name "$CANARY_SQS_QUEUE" --region "$AWS_REGION" &>/dev/null; then
    warn "SQS queues lost — re-seeding..."
    run_seeder "$SEEDER_QUEUES" 2>&1 | tail -3
    ok "SQS queues re-seeded"
  fi

  # Secrets Manager
  if ! aws --endpoint-url="$LS" secretsmanager get-secret-value \
       --secret-id "$CANARY_SECRET_ID" --region "$AWS_REGION" &>/dev/null; then
    warn "Secrets lost — re-seeding..."
    run_seeder "$SEEDER_SECRETS" 2>&1 | tail -3
    ok "Secrets re-seeded"
  fi

  # API Gateway keys (depend on secrets for encryption)
  api_key_count=$(aws --endpoint-url="$LS" apigateway get-api-keys --region "$AWS_REGION" \
                  --query 'length(items)' --output text 2>/dev/null || echo "0")
  if [ "$api_key_count" = "0" ] || [ "$api_key_count" = "None" ]; then
    warn "API Gateway keys lost — re-seeding..."
    run_seeder "$SEEDER_API_KEYS" 2>&1 | tail -3
    ok "API keys re-seeded"
  fi
}

# Ensure shared modules are built (smart: skips if dist/ is up to date)
ensure_shared_modules() {
  [ ! -d "$SHARED_MODULES_DIR" ] && return 0

  for mod_dir in "$SHARED_MODULES_DIR"/*/; do
    [ ! -d "$mod_dir/.git" ] && continue
    [ ! -f "$mod_dir/package.json" ] && continue
    grep -q '"build"' "$mod_dir/package.json" 2>/dev/null || continue

    mod_name=$(basename "$mod_dir")

    # Find dist/ (root or workspace packages)
    dist_dir="$mod_dir/dist"
    if [ ! -d "$dist_dir" ] && [ -d "$mod_dir/packages" ]; then
      dist_dir=$(find "$mod_dir/packages" -maxdepth 2 -name "dist" -type d | head -1)
    fi

    # No dist/ → must build
    if [ -z "$dist_dir" ] || [ ! -d "$dist_dir" ]; then
      info "$mod_name — building (no dist/)..."
      (cd "$mod_dir" && npm install --silent 2>/dev/null && npm run build 2>&1 | tail -3)
      ok "$mod_name built"
      continue
    fi

    # Check if source is newer than dist/
    build_marker="$dist_dir/index.js"
    [ ! -f "$build_marker" ] && build_marker="$dist_dir/index.d.ts"
    [ ! -f "$build_marker" ] && build_marker=$(find "$dist_dir" -name "*.js" -type f | head -1)
    [ -z "$build_marker" ] && continue

    newer_src=$(find "$mod_dir/src" "$mod_dir/packages" -name "*.ts" -not -name "*.d.ts" -newer "$build_marker" 2>/dev/null | head -1)
    if [ -n "$newer_src" ]; then
      info "$mod_name — rebuilding (source changed)..."
      (cd "$mod_dir" && npm install --silent 2>/dev/null && npm run build 2>&1 | tail -3)
      ok "$mod_name rebuilt"
    fi
  done
}

# Check if a service needs infrastructure
svc_needs_infra() {
  for dep in "${SVC_INFRA_DEPENDENT[@]}"; do
    [ "$dep" = "$1" ] && return 0
  done
  return 1
}

# Wait for a port to become available (up to $2 seconds, default 30)
wait_for_port() {
  local port="$1" timeout="${2:-30}"
  for i in $(seq 1 "$timeout"); do
    if lsof -ti:"$port" &>/dev/null; then return 0; fi
    sleep 1
  done
  return 1
}

# Wait for a string to appear in a log file
wait_for_log() {
  local log_file="$1" pattern="$2" timeout="${3:-30}"
  for i in $(seq 1 "$timeout"); do
    if grep -q "$pattern" "$log_file" 2>/dev/null; then return 0; fi
    sleep 1
  done
  return 1
}

# Kill processes on a given port
kill_port() {
  lsof -ti:"$1" 2>/dev/null | xargs kill -9 2>/dev/null || true
}

# Check if a port is in use
port_is_busy() {
  lsof -ti:"$1" &>/dev/null
}

# Check if a docker container is running
container_is_running() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${1}$"
}

# Start a process-managed service (background, with log)
start_process_service() {
  local svc="$1"
  local dir="$CAL_PROJECT/${SVC_DIR[$svc]}"
  local cmd="${SVC_START[$svc]}"
  local log="${SVC_LOG[$svc]}"
  local port="${SVC_PORT[$svc]}"
  local label="${SVC_LABEL[$svc]}"

  [ ! -d "$dir" ] && { warn "$label directory not found: $dir"; return 1; }

  > "$log"  # truncate log
  (cd "$dir" && $cmd > "$log" 2>&1 &)

  if [ "$port" -gt 0 ]; then
    if wait_for_log "$log" "Server ready" 45; then
      ok "$label ready on :$port"
    else
      warn "$label may still be starting — check: tail -f $log"
    fi
  else
    ok "$label started — check: tail -f $log"
  fi
}

# Start a docker-managed service
start_docker_service() {
  local svc="$1"
  local container="${SVC_CONTAINER[$svc]}"
  local label="${SVC_LABEL[$svc]}"
  local port="${SVC_PORT[$svc]}"

  if container_is_running "$container"; then
    ok "$label already running on :$port"
    return
  fi

  # Map service alias to compose service name
  compose_name=""
  case "$svc" in
    admin)     compose_name="be-admin" ;;
    fe)        compose_name="fe" ;;
    docs)      compose_name="docs" ;;
    dynamo-gui) compose_name="dynamo-gui" ;;
    webhooks)  compose_name="webhook-tester" ;;
  esac

  # Start via compose (all profiles so any service can be targeted)
  dc --profile app --profile docs --profile tools up -d "$(
    echo "$compose_name"
  )" 2>/dev/null
  ok "$label started"

  # Post-start: seed webhook URLs into the database
  if [ "$svc" = "webhooks" ]; then
    for i in $(seq 1 10); do
      curl -sf "$WEBHOOK_BASE_URL/api/session" -o /dev/null 2>/dev/null && break
      sleep 1
    done
    info "Seeding webhook URLs for main client..."
    run_seeder "$SEEDER_WEBHOOKS" 2>&1 | tail -3
    ok "Webhook URLs seeded"
  fi
}

# Stop a process-managed service
stop_process_service() {
  local svc="$1"
  local port="${SVC_PORT[$svc]}"
  local label="${SVC_LABEL[$svc]}"

  if [ "$port" -gt 0 ]; then
    if port_is_busy "$port"; then
      kill_port "$port"
      ok "$label stopped (port $port)"
    else
      dim "$label not running"
    fi
  else
    # No port (e.g. risk-scoring) — kill by process pattern
    local dir="${SVC_DIR[$svc]}"
    if pgrep -f "$dir" &>/dev/null; then
      pgrep -f "$dir" | xargs kill -9 2>/dev/null || true
      ok "$label stopped"
    else
      dim "$label not running"
    fi
  fi
}

# Stop a docker-managed service
stop_docker_service() {
  local svc="$1"
  local container="${SVC_CONTAINER[$svc]}"
  local label="${SVC_LABEL[$svc]}"

  if container_is_running "$container"; then
    docker stop "$container" &>/dev/null
    ok "$label stopped"
  else
    dim "$label not running"
  fi
}
