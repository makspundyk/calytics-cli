#!/bin/bash
# cal restart <service>
# Restart a single service (kill + start).

target="${1:-}"
[ -z "$target" ] && fail "Usage: cal restart <service> (be, a2a, rs, admin, fe, docs)"

svc=$(svc_resolve "$target") || fail "Unknown service: $target"
label="${SVC_LABEL[$svc]}"

phase "Restarting $label"

if svc_is_process "$svc"; then
  stop_process_service "$svc"
  sleep 1
  start_process_service "$svc"
elif svc_is_docker "$svc"; then
  stop_docker_service "$svc"
  start_docker_service "$svc"
fi
