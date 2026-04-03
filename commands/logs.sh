#!/bin/bash
# cal logs <service>
# Tail last 80 lines + follow. Press Ctrl+C to stop.
#
# Examples:
#   cal logs be       Tail calytics-be logs
#   cal logs dg       Same as above (alias)
#   cal logs a2a      Tail calytics-a2a logs
#   cal logs rs       Tail calytics-risk-scoring logs
#   cal logs admin    Tail be-admin container logs
#   cal logs fe       Tail frontend container logs

target="${1:-}"
[ -z "$target" ] && fail "Usage: cal logs <service> (be, dg, a2a, rs, admin, fe, docs)"

svc=$(svc_resolve "$target") || fail "Unknown service: $target"
label="${SVC_LABEL[$svc]}"

if svc_is_docker "$svc"; then
  container="${SVC_CONTAINER[$svc]}"
  info "Tailing $label (Ctrl+C to stop)"
  exec docker logs --tail 80 -f "$container" 2>&1
elif svc_is_process "$svc"; then
  log="${SVC_LOG[$svc]}"
  if [ -f "$log" ]; then
    info "Tailing $log (Ctrl+C to stop)"
    exec tail -n 80 -f "$log"
  else
    warn "No log file: $log — is $label running?"
  fi
fi
