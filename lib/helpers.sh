#!/bin/bash
# Shared utility functions

# Derived paths (from CAL_ROOT and CAL_PROJECT, set by cal.sh)
COMPOSE_FILE="$CAL_ROOT/infra/docker-compose.yml"
COMPOSE_ENV="$CAL_PROJECT/.env"
COMPOSE_PROJECT="calytics"        # fixed name — docker compose uses dir name by default, we override to stay consistent
SEEDERS_DIR="$CAL_ROOT/seeders"

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

  # Re-seed SQS queues if lost
  if ! aws --endpoint-url="http://localhost:${INFRA_LOCALSTACK_PORT}" sqs get-queue-url \
       --queue-name "calytics-be-local-data-enrichment.fifo" --region "$AWS_REGION" &>/dev/null; then
    warn "SQS queues lost — re-seeding..."
    bash "$SEEDERS_DIR/queues.sh" 2>&1 | tail -3
    ok "SQS queues re-seeded"
  fi
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

  # Standalone containers (not in docker-compose)
  case "$svc" in
    dynamo-gui)
      docker run -d --rm \
        --name "$container" \
        -p "$port:8001" \
        -e DYNAMO_ENDPOINT="http://host.docker.internal:${INFRA_LOCALSTACK_PORT}" \
        -e AWS_REGION="$AWS_REGION" \
        -e AWS_ACCESS_KEY_ID=test \
        -e AWS_SECRET_ACCESS_KEY=test \
        aaronshaf/dynamodb-admin &>/dev/null
      ok "$label started on :$port"
      return
      ;;
  esac

  # Compose-managed containers
  dc --profile app --profile docs up -d "$(
    case "$svc" in
      admin) echo "be-admin" ;;
      fe)    echo "fe" ;;
      docs)  echo "docs" ;;
    esac
  )" 2>/dev/null
  ok "$label started"
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
