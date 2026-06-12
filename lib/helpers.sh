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
  if ! infra_is_running; then
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
  fi

  # Verify LocalStack resources exist (ephemeral — can disappear while container stays up)
  LS="http://localhost:${INFRA_LOCALSTACK_PORT}"

  # SQS queues — check one canary per service (BE + A2A) so neither can silently go missing
  local missing_queue=""
  for q in "${CANARY_SQS_QUEUES[@]}"; do
    if ! aws --endpoint-url="$LS" sqs get-queue-url \
         --queue-name "$q" --region "$AWS_REGION" &>/dev/null; then
      missing_queue="$q"
      break
    fi
  done
  if [ -n "$missing_queue" ]; then
    warn "SQS queues lost ($missing_queue missing) — re-seeding..."
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
# Auto-retries on transient Serverless API license-check timeouts (v4 phones home each run).
start_process_service() {
  local svc="$1"
  local dir="$CAL_PROJECT/${SVC_DIR[$svc]}"
  local cmd="${SVC_START[$svc]}"
  local log="${SVC_LOG[$svc]}"
  local port="${SVC_PORT[$svc]}"
  local label="${SVC_LABEL[$svc]}"

  [ ! -d "$dir" ] && { warn "$label directory not found: $dir"; return 1; }

  # Declared in lib/names.sh (SVC_USES_SERVERLESS). These services hit the v4 license API on start.
  local uses_sls=0
  svc_uses_serverless "$svc" && uses_sls=1

  local max_attempts=3 attempt=1
  local ready_timeout=120  # A2A runs `npm run build &&` first, so allow generous TS compile window
  while [ "$attempt" -le "$max_attempts" ]; do
    > "$log"  # truncate log
    # Source the per-service .env (if present) so process env carries every
    # NEW_*_TABLE_NAME / NEW_*_SECRET_ID the service expects. Otherwise the SDK
    # falls back to its hardcoded defaults (which point at non-existent tables
    # locally, e.g. AIS_SESSION_CONNECTIONS_TABLE_NAME → 'ais-connection-...'),
    # and adapters silently fail-closed. Subshell-scoped so we never pollute the
    # CLI session env or sibling services.
    (cd "$dir" && [ -f .env ] && set -a && . ./.env >/dev/null 2>&1 && set +a; exec $cmd > "$log" 2>&1 &)

    # Single loop: wait for either "Server ready" or the transient SLS license-check failure.
    # The failure can surface late (A2A does `npm run build` before invoking serverless).
    local outcome=pending
    for _ in $(seq 1 "$ready_timeout"); do
      sleep 1
      # Readiness for port-bound services. Two patterns:
      #   - HTTP API services (be, a2a): wait for "Server ready" — Nest boots after the lambda port opens.
      #   - Pure event-driven services (cp): no HTTP routes, so serverless-offline never prints "Server ready";
      #     the only listener is the lambda invoke port. Detect via "listening on http" + the registered port
      #     actually being busy. The port_is_busy guard keeps be/a2a from being marked ready prematurely
      #     (their lambda port opens before the HTTP API on SVC_PORT is up).
      if [ "$port" -gt 0 ] && grep -q "Server ready" "$log" 2>/dev/null; then
        outcome=ready
        break
      fi
      if [ "$port" -gt 0 ] && grep -q "listening on" "$log" 2>/dev/null && port_is_busy "$port"; then
        outcome=ready
        break
      fi
      if [ "$uses_sls" -eq 1 ] && grep -qE 'Unable to reach the Serverless API|ETIMEDOUT|fetch failed' "$log" 2>/dev/null; then
        outcome=sls_fail
        break
      fi
      # Port-less services (rs stream): once the process prints output and stays up, treat as ready.
      if [ "$port" -eq 0 ] && [ "$(wc -c < "$log" 2>/dev/null || echo 0)" -gt 200 ]; then
        # Give it one more second to surface any immediate failure, then declare ok
        sleep 1
        if [ "$uses_sls" -eq 1 ] && grep -qE 'Unable to reach the Serverless API|ETIMEDOUT|fetch failed' "$log" 2>/dev/null; then
          outcome=sls_fail
        else
          outcome=ready_noport
        fi
        break
      fi
    done

    case "$outcome" in
      ready)
        ok "$label ready on :$port"
        return 0
        ;;
      ready_noport)
        ok "$label started — check: tail -f $log"
        return 0
        ;;
      sls_fail)
        warn "$label: Serverless API unreachable (attempt $attempt/$max_attempts) — retrying..."
        [ "$port" -gt 0 ] && kill_port "$port"
        pgrep -f "${SVC_DIR[$svc]}" 2>/dev/null | xargs -r kill -9 2>/dev/null || true
        attempt=$((attempt + 1))
        sleep 2
        continue
        ;;
      pending)
        warn "$label may still be starting — check: tail -f $log"
        return 0
        ;;
    esac
  done

  warn "$label: Serverless API unreachable after $max_attempts attempts."
  warn "  Network to api.serverless.com is flaky. Options:"
  warn "    1) Retry: cal restart $svc"
  warn "    2) Set a headless key: export SERVERLESS_ACCESS_KEY=<key from app.serverless.com>"
  warn "    3) Downgrade to license-free: npm i -D serverless@3  (in ${SVC_DIR[$svc]})"
  return 1
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

  # Start via compose (all profiles so any service can be targeted).
  # --renew-anon-volumes: the app services bind-mount the repo and keep
  # node_modules in an anonymous volume; without -V a recreate keeps the OLD
  # volume and the container runs stale dependencies even after a rebuild
  # with a changed lockfile.
  dc --profile app --profile docs --profile tools up --build -d --renew-anon-volumes "$(
    echo "$compose_name"
  )" 2>/dev/null
  ok "$label started"

  # Post-start: wait for webhook-tester, then seed callback URLs into the DB
  if [ "$svc" = "webhooks" ]; then
    for i in $(seq 1 10); do
      curl -sf "$WEBHOOK_BASE_URL/healthz" -o /dev/null 2>/dev/null && break
      sleep 1
    done
    info "Seeding webhook URLs for main client..."
    run_seeder "$SEEDER_WEBHOOKS" 2>&1 | tail -3
    ok "Webhook URLs seeded"
  fi
}

# Kill a process and all of its descendants (children first)
kill_tree() {
  local pid="$1" child
  for child in $(pgrep -P "$pid" 2>/dev/null); do kill_tree "$child"; done
  kill -9 "$pid" 2>/dev/null || true
}

# Kill a service's process tree by repo-path pattern. Catches mid-startup
# trees whose port isn't bound yet (npm build phase) and portless services.
# Matches are filtered to known runtimes so an editor or shell that merely
# has the repo path in its argv is never touched.
kill_service_pattern() {
  local dir="$1" pid cmd killed=1
  # Trailing slash so "/calytics-be/" never matches calytics-be-admin paths
  for pid in $(pgrep -f "/${dir}/" 2>/dev/null); do
    cmd=$(ps -o comm= -p "$pid" 2>/dev/null | sed 's|.*/||')
    case "$cmd" in
      node|npm|npx|sh|bash|tsx|serverless*|esbuild*)
        kill_tree "$pid"
        killed=0
        ;;
    esac
  done
  return $killed
}

# Stop a process-managed service
stop_process_service() {
  local svc="$1"
  local port="${SVC_PORT[$svc]}"
  local label="${SVC_LABEL[$svc]}"
  local dir="${SVC_DIR[$svc]}"

  if [ "$port" -gt 0 ] && port_is_busy "$port"; then
    # Running service: kill the port-holder; parents (npm/sh) exit with it
    kill_port "$port"
    ok "$label stopped (port $port)"
  elif kill_service_pattern "$dir"; then
    # Port not bound: the service is either portless (rs) or still mid-startup
    # (npm build before serverless binds) — sweep the tree by repo path
    ok "$label stopped (startup tree)"
  else
    dim "$label not running"
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
