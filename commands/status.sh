#!/bin/bash
# cal status
# Show the state of all services, infrastructure, and ports.

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
  port="${SVC_PORT[$svc]}"
  url="${SVC_URL[$svc]:-}"
  is_running=false

  if svc_is_docker "$svc"; then
    container="${SVC_CONTAINER[$svc]}"
    container_is_running "$container" && is_running=true
  elif svc_is_process "$svc"; then
    if [ "$port" -gt 0 ] && port_is_busy "$port"; then
      is_running=true
    elif [ "$port" -eq 0 ] && pgrep -f "${SVC_DIR[$svc]}" &>/dev/null; then
      is_running=true
    fi
  fi

  if [ "$is_running" = true ]; then
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

# Credentials
echo -e "  ${BOLD}Credentials${NC}"
echo -e "    Client:  $CRED_CLIENT_EMAIL / $CRED_CLIENT_PASS"
echo -e "    Admin:   $CRED_ADMIN_EMAIL / $CRED_ADMIN_PASS"
echo ""
