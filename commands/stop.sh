#!/bin/bash
# cal stop [service|all|infra|everything]
# Stop services gracefully. Data is preserved (volumes are kept).
#
# Targets:
#   cal stop              Stop all application services (not infra)
#   cal stop all          Same as above
#   cal stop be           Stop a single service
#   cal stop infra        Stop LocalStack + Postgres (data preserved)
#   cal stop everything   Stop all services + infrastructure

target="${1:-all}"

case "$target" in
  everything)
    phase "Stopping everything"
    for svc in "${SVC_ALL_LIST[@]}"; do
      if svc_is_process "$svc"; then
        stop_process_service "$svc"
      elif svc_is_docker "$svc"; then
        stop_docker_service "$svc"
      fi
    done
    info "Stopping infrastructure..."
    docker stop "$INFRA_LOCALSTACK_CONTAINER" 2>/dev/null && ok "LocalStack stopped" || dim "LocalStack not running"
    docker stop "$INFRA_POSTGRES_CONTAINER" 2>/dev/null && ok "PostgreSQL stopped" || dim "PostgreSQL not running"
    ok "Everything stopped (data preserved in Docker volumes)"
    ;;

  infra)
    phase "Stopping infrastructure"
    docker stop "$INFRA_LOCALSTACK_CONTAINER" 2>/dev/null && ok "LocalStack stopped" || dim "LocalStack not running"
    docker stop "$INFRA_POSTGRES_CONTAINER" 2>/dev/null && ok "PostgreSQL stopped" || dim "PostgreSQL not running"
    info "Data preserved — secrets, queues, tables will be there on restart"
    ;;

  all)
    phase "Stopping all services"
    for svc in "${SVC_ALL_LIST[@]}"; do
      if svc_is_process "$svc"; then
        stop_process_service "$svc"
      elif svc_is_docker "$svc"; then
        stop_docker_service "$svc"
      fi
    done
    ok "All services stopped (infrastructure still running)"
    ;;

  *)
    svc=$(svc_resolve "$target") || fail "Unknown service: $target (try: be, a2a, rs, admin, fe, docs, infra, everything)"

    if svc_is_process "$svc"; then
      stop_process_service "$svc"
    elif svc_is_docker "$svc"; then
      stop_docker_service "$svc"
    fi
    ;;
esac
