#!/bin/bash
# cal status [service]
# Show the state of all services or detailed info for one service.
#
# Examples:
#   cal status            Show all services, infra, webhooks, credentials
#   cal status be         Detailed status for calytics-be
#   cal status webhooks   Webhook tester sessions + request counts

target="${1:-}"

# ── Helper: check if a service is running ────────────────────────
_svc_running() {
  svc="$1"
  if svc_is_docker "$svc"; then
    container_is_running "${SVC_CONTAINER[$svc]}"
  elif svc_is_process "$svc"; then
    port="${SVC_PORT[$svc]}"
    if [ "$port" -gt 0 ]; then
      port_is_busy "$port"
    else
      pgrep -f "${SVC_DIR[$svc]}" &>/dev/null
    fi
  fi
}

# ── Single service status ────────────────────────────────────────
if [ -n "$target" ]; then
  svc=$(svc_resolve "$target") || fail "Unknown service: $target"
  label="${SVC_LABEL[$svc]}"
  port="${SVC_PORT[$svc]}"
  url="${SVC_URL[$svc]:-}"

  echo ""
  echo -e "  ${BOLD}$label${NC}"
  echo ""

  if _svc_running "$svc"; then
    echo -e "  Status:     ${GREEN}running${NC}"
  else
    echo -e "  Status:     ${RED}stopped${NC}"
  fi

  [ "$port" -gt 0 ] && echo -e "  Port:       :$port"
  [ -n "$url" ] && echo -e "  URL:        ${CYAN}$url${NC}"

  # Service dir
  dir_name="${SVC_DIR[$svc]:-}"
  [ -n "$dir_name" ] && echo -e "  Directory:  $dir_name/"

  # Container or PID
  if svc_is_docker "$svc"; then
    container="${SVC_CONTAINER[$svc]}"
    echo -e "  Container:  $container"
    if container_is_running "$container"; then
      uptime=$(docker inspect --format='{{.State.StartedAt}}' "$container" 2>/dev/null | cut -dT -f1,2 | tr T ' ')
      echo -e "  Started:    $uptime"
    fi
  elif svc_is_process "$svc"; then
    log="${SVC_LOG[$svc]:-}"
    [ -n "$log" ] && echo -e "  Log:        $log"
  fi

  # Webhook-specific: show sessions + request counts
  if [ "$svc" = "webhooks" ] && _svc_running "$svc"; then
    echo ""
    echo -e "  ${BOLD}Sessions${NC}"
    echo -e "    DebitGuard:       ${CYAN}${WEBHOOK_URL_DG}${NC}"
    echo -e "    OwnershipCheck:   ${CYAN}${WEBHOOK_URL_OC}${NC}"
    echo -e "    A2A + CC:         ${CYAN}${WEBHOOK_URL_A2A}${NC}"
    echo ""
    echo -e "  ${BOLD}Requests received${NC}"
    for session_name in "DG:$WEBHOOK_SESSION_DG" "OC:$WEBHOOK_SESSION_OC" "A2A:$WEBHOOK_SESSION_A2A"; do
      name="${session_name%%:*}"
      uuid="${session_name##*:}"
      count=$(find "$WEBHOOK_DATA_DIR/$uuid" -name "request.*.json" 2>/dev/null | wc -l)
      echo -e "    $name: $count requests"
    done
    echo ""
    echo -e "  ${BOLD}Data directory${NC}"
    echo -e "    $WEBHOOK_DATA_DIR/"
    echo -e "    ${DIM}(files readable by LLM / scripts)${NC}"
  fi

  echo ""
  exit 0
fi

# ── Full status (no argument) ────────────────────────────────────
echo ""
echo -e "${BOLD}  Calytics Local Environment${NC}"
echo ""

# Infrastructure
echo -e "  ${BOLD}Infrastructure${NC}"
if container_is_running "$INFRA_LOCALSTACK_CONTAINER"; then
  echo -e "    LocalStack      ${GREEN}running${NC}  :${INFRA_LOCALSTACK_PORT}"
else
  echo -e "    LocalStack      ${RED}stopped${NC}"
fi
if container_is_running "$INFRA_POSTGRES_CONTAINER"; then
  echo -e "    PostgreSQL      ${GREEN}running${NC}  :${INFRA_POSTGRES_PORT}"
else
  echo -e "    PostgreSQL      ${RED}stopped${NC}"
fi
echo ""

# Services
echo -e "  ${BOLD}Services${NC}"
for svc in "${SVC_ALL_LIST[@]}"; do
  label=$(printf "%-20s" "${SVC_LABEL[$svc]}")
  url="${SVC_URL[$svc]:-}"

  if _svc_running "$svc"; then
    if [ -n "$url" ]; then
      echo -e "    $label ${GREEN}running${NC}  ${CYAN}${url}${NC}"
    else
      echo -e "    $label ${GREEN}running${NC}"
    fi
  else
    echo -e "    $label ${RED}stopped${NC}"
  fi
done
echo ""

# Webhooks summary (if running)
if _svc_running "webhooks"; then
  echo -e "  ${BOLD}Webhook Endpoints${NC}"
  echo -e "    DG:   ${CYAN}${WEBHOOK_URL_DG}${NC}"
  echo -e "    OC:   ${CYAN}${WEBHOOK_URL_OC}${NC}"
  echo -e "    A2A:  ${CYAN}${WEBHOOK_URL_A2A}${NC}"
  echo -e "    UI:   ${CYAN}${WEBHOOK_BASE_URL}${NC}"
  echo ""
fi

# Credentials
echo -e "  ${BOLD}Credentials${NC}"
echo -e "    Client:  $CRED_CLIENT_EMAIL / $CRED_CLIENT_PASS"
echo -e "    Admin:   $CRED_ADMIN_EMAIL / $CRED_ADMIN_PASS"
echo ""
