#!/bin/bash
# cal stop [service|services]
# Stop services and/or infrastructure.
#
# Targets:
#   cal stop              Stop all app services (keeps infra)
#   cal stop infra        Stop everything (services + infra)
#   cal stop <service>    Stop one service

target="${1:-all}"

stop_all_services() {
  for svc in "${SVC_ALL_LIST[@]}"; do
    if svc_is_process "$svc"; then
      stop_process_service "$svc"
    elif svc_is_docker "$svc"; then
      stop_docker_service "$svc"
    fi
  done
}

stop_infra() {
  info "Stopping infrastructure..."
  docker stop "$INFRA_LOCALSTACK_CONTAINER" 2>/dev/null && ok "LocalStack stopped" || dim "LocalStack not running"
  docker stop "$INFRA_POSTGRES_CONTAINER" 2>/dev/null && ok "PostgreSQL stopped" || dim "PostgreSQL not running"
}

case "$target" in
  all)
    phase "Stopping all services"
    stop_all_services
    ok "All services stopped (infra still running)"
    ;;

  infra)
    phase "Stopping everything (services + infra)"
    stop_all_services
    stop_infra
    ok "Everything stopped (data preserved in Docker volumes)"
    ;;

  *)
    svc=$(svc_resolve "$target") || fail "Unknown: $target (try: be, a2a, rs, admin, fe, docs, dynamo-gui, services)"

    if svc_is_process "$svc"; then
      stop_process_service "$svc"
    elif svc_is_docker "$svc"; then
      stop_docker_service "$svc"
    fi
    ;;
esac
