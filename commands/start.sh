#!/bin/bash
# cal start [service|all]
# Start one or all services. Docker services via compose, process services as background jobs.

target="${1:-all}"

if [ "$target" = "all" ]; then
  phase "Starting all services"

  # Kill leftover processes on app ports
  for port in 9000 5000 3333 3000; do
    kill_port "$port"
  done

  # Docker services
  info "Starting Docker services (admin, fe)..."
  docker compose -f "$COMPOSE_FILE" --env-file "$COMPOSE_ENV" --profile app up -d 2>/dev/null
  ok "Docker services started"

  # Process services
  for svc in "${SVC_PROCESS_LIST[@]}"; do
    local dir="$CAL_PROJECT/${SVC_DIR[$svc]}"
    [ ! -d "$dir" ] && continue
    info "Starting ${SVC_LABEL[$svc]}..."
    start_process_service "$svc"
  done

  ok "All services started"
else
  svc=$(svc_resolve "$target") || fail "Unknown service: $target (try: be, a2a, rs, admin, fe, docs)"

  phase "Starting ${SVC_LABEL[$svc]}"

  if svc_is_docker "$svc"; then
    start_docker_service "$svc"
  elif svc_is_process "$svc"; then
    local port="${SVC_PORT[$svc]}"
    [ "$port" -gt 0 ] && kill_port "$port"
    start_process_service "$svc"
  fi
fi
