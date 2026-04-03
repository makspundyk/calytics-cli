#!/bin/bash
# cal start [service|all|infra]
# Start one or all services. Docker services via compose, process services as background jobs.
#
# Targets:
#   cal start             Start all application services
#   cal start all         Same as above
#   cal start be          Start a single service
#   cal start infra       Start LocalStack + Postgres (re-seeds SQS queues if needed)

target="${1:-all}"

case "$target" in
  infra)
    phase "Starting infrastructure"

    # Start containers
    info "Starting LocalStack + Postgres..."
    docker start "$INFRA_LOCALSTACK_CONTAINER" 2>/dev/null || dc up -d localstack postgres 2>/dev/null
    docker start "$INFRA_POSTGRES_CONTAINER" 2>/dev/null || true

    # Wait for LocalStack health
    info "Waiting for LocalStack..."
    for i in $(seq 1 30); do
      if curl -sf http://localhost:${INFRA_LOCALSTACK_PORT}/_localstack/health 2>/dev/null | grep -q '"dynamodb"'; then
        ok "LocalStack healthy"
        break
      fi
      [ "$i" -eq 30 ] && warn "LocalStack may still be starting"
      sleep 1
    done

    # Wait for Postgres
    for i in $(seq 1 15); do
      if docker exec "$INFRA_POSTGRES_CONTAINER" pg_isready -U postgres -d calytics-admin -q 2>/dev/null; then
        ok "PostgreSQL healthy"
        break
      fi
      sleep 1
    done

    # SQS queues don't survive LocalStack restart — re-seed if missing
    if ! aws --endpoint-url="http://localhost:${INFRA_LOCALSTACK_PORT}" sqs get-queue-url \
         --queue-name "calytics-be-local-data-enrichment.fifo" --region "$AWS_REGION" &>/dev/null; then
      warn "SQS queues lost (LocalStack doesn't persist them) — re-seeding..."
      bash "$SEEDERS_DIR/queues.sh" 2>&1 | tail -3
      ok "SQS queues re-seeded"
    else
      ok "SQS queues intact"
    fi
    ;;

  all)
    phase "Starting all services"

    # Kill leftover processes on app ports
    for port in 9000 5000 3333 3000; do
      kill_port "$port"
    done

    # Docker services
    info "Starting Docker services (admin, fe)..."
    dc --profile app up -d 2>/dev/null
    ok "Docker services started"

    # Process services
    for svc in "${SVC_PROCESS_LIST[@]}"; do
      dir="$CAL_PROJECT/${SVC_DIR[$svc]}"
      [ ! -d "$dir" ] && continue
      info "Starting ${SVC_LABEL[$svc]}..."
      start_process_service "$svc"
    done

    ok "All services started"
    ;;

  *)
    svc=$(svc_resolve "$target") || fail "Unknown service: $target (try: be, a2a, rs, admin, fe, docs, infra)"

    phase "Starting ${SVC_LABEL[$svc]}"

    if svc_is_docker "$svc"; then
      start_docker_service "$svc"
    elif svc_is_process "$svc"; then
      port="${SVC_PORT[$svc]}"
      [ "$port" -gt 0 ] && kill_port "$port"
      start_process_service "$svc"
    fi
    ;;
esac
