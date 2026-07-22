#!/bin/bash
# cal callbacks drain
# Drain the client-callback SQS queue through the be-admin client-callback ingress
# lambda (SQS -> handler -> webhook delivery). Locally be-admin runs only as an HTTP
# server, so nothing invokes the SQS event-source ingress — this command reproduces
# that leg: it receives messages, invokes the compiled ingress handler inside the
# be-admin container, and deletes the messages that were settled (delivered or dropped;
# retryable failures are left on the queue).
#
# Use it after emitting client webhooks (e.g. payment_reconciliation.transaction.*) to
# deliver them to the subscribed webhook URLs (webhook-tester / client callback URLs).

action="${1:-drain}"

case "$action" in
  drain)
    container="${SVC_CONTAINER[admin]}"
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
      fail "be-admin is not running — start it first with: cal start admin"
    fi
    script="$CAL_ROOT/infra/drain-client-callbacks.js"
    [[ -f "$script" ]] || fail "drain script not found: $script"
    info "Draining client-callback queue through the be-admin ingress consumer..."
    docker cp "$script" "${container}:/app/drain-client-callbacks.js" >/dev/null 2>&1 \
      || fail "failed to copy drain script into ${container}"
    docker exec -w /app "$container" node /app/drain-client-callbacks.js \
      || fail "callback drain failed"
    ok "Client-callback queue drained"
    ;;
  *)
    fail "Unknown callbacks action: $action (expected: drain)"
    ;;
esac
