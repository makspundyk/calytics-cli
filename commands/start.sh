#!/bin/bash
# cal start [service|infra]
# Start services. Auto-starts infra for dependent services.
#
# Targets:
#   cal start             Start all (infra + all services)
#   cal start infra       Start just LocalStack + Postgres
#   cal start <service>   Start one service (auto-starts infra if needed)

target="${1:-all}"

case "$target" in
  infra)
    phase "Starting infrastructure"
    ensure_infra
    ensure_shared_modules
    ;;

  all)
    phase "Starting all"

    # Infra first
    ensure_infra
    ensure_shared_modules

    # Kill leftover processes on app ports
    for svc in "${SVC_PROCESS_LIST[@]}"; do
      port="${SVC_PORT[$svc]}"
      [ "$port" -gt 0 ] && kill_port "$port"
    done

    # Docker services (compose-managed)
    info "Starting Docker services..."
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
    svc=$(svc_resolve "$target") || fail "Unknown service: $target (try: be, a2a, rs, admin, fe, docs, dynamo-gui, infra)"

    phase "Starting ${SVC_LABEL[$svc]}"

    # Auto-start infra for dependent services
    if svc_needs_infra "$svc"; then
      ensure_infra
    fi

    if svc_is_docker "$svc"; then
      start_docker_service "$svc"
    elif svc_is_process "$svc"; then
      port="${SVC_PORT[$svc]}"
      [ "$port" -gt 0 ] && kill_port "$port"
      start_process_service "$svc"
    fi
    ;;
esac
