#!/bin/bash
# cal stop [service|all]
# Stop one or all services gracefully. Data is preserved.

target="${1:-all}"

if [ "$target" = "all" ]; then
  phase "Stopping all services"
  for svc in "${SVC_ALL_LIST[@]}"; do
    if svc_is_process "$svc"; then
      stop_process_service "$svc"
    elif svc_is_docker "$svc"; then
      stop_docker_service "$svc"
    fi
  done
  ok "All services stopped"
else
  svc=$(svc_resolve "$target") || fail "Unknown service: $target"

  if svc_is_process "$svc"; then
    stop_process_service "$svc"
  elif svc_is_docker "$svc"; then
    stop_docker_service "$svc"
  fi
fi
