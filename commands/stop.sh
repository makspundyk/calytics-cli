#!/bin/bash
# cal stop [service|services]
# Stop services and/or infrastructure.
#
# Targets:
#   cal stop              Stop everything (services + infra)
#   cal stop services     Stop app services only (keep infra running)
#   cal stop <service>    Stop one service

target="${1:-}"

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
  "")
    # No argument = stop everything
    phase "Stopping everything"
    stop_all_services
    stop_infra
    ok "Everything stopped (data preserved in Docker volumes)"
    ;;

  services)
    phase "Stopping all services (keeping infra)"
    stop_all_services
    ok "Services stopped — infra still running"
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
