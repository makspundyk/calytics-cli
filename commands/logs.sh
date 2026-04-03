#!/bin/bash
# cal logs <service>
# Tail logs for a service. Press Ctrl+C to stop.

target="${1:-}"
[ -z "$target" ] && fail "Usage: cal logs <service> (be, a2a, rs, admin, fe, docs)"

svc=$(svc_resolve "$target") || fail "Unknown service: $target"
label="${SVC_LABEL[$svc]}"

if svc_is_docker "$svc"; then
  container="${SVC_CONTAINER[$svc]}"
  info "Tailing $label container logs (Ctrl+C to stop)"
  docker logs -f "$container" 2>&1
elif svc_is_process "$svc"; then
  log="${SVC_LOG[$svc]}"
  if [ -f "$log" ]; then
    info "Tailing $log (Ctrl+C to stop)"
    tail -f "$log"
  else
    warn "No log file found: $log"
    warn "Is $label running?"
  fi
fi
