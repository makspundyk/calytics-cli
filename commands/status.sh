#!/bin/bash
# cal status
# Show the state of all services, infrastructure, and ports.

echo ""
echo -e "${BOLD}  Calytics Local Environment${NC}"
echo ""

# Infrastructure
echo -e "  ${BOLD}Infrastructure${NC}"
if container_is_running "localstack_main"; then
  echo -e "    LocalStack      ${GREEN}running${NC}  :4566"
else
  echo -e "    LocalStack      ${RED}stopped${NC}"
fi
if container_is_running "calytics_postgres"; then
  echo -e "    PostgreSQL      ${GREEN}running${NC}  :5432"
else
  echo -e "    PostgreSQL      ${RED}stopped${NC}"
fi
echo ""

# Services
echo -e "  ${BOLD}Services${NC}"
for svc in "${SVC_ALL_LIST[@]}"; do
  label=$(printf "%-20s" "${SVC_LABEL[$svc]}")
  port="${SVC_PORT[$svc]}"

  if svc_is_docker "$svc"; then
    container="${SVC_CONTAINER[$svc]}"
    if container_is_running "$container"; then
      echo -e "    $label ${GREEN}running${NC}  :$port"
    else
      echo -e "    $label ${RED}stopped${NC}"
    fi
  elif svc_is_process "$svc"; then
    if [ "$port" -gt 0 ] && port_is_busy "$port"; then
      echo -e "    $label ${GREEN}running${NC}  :$port"
    elif [ "$port" -eq 0 ] && pgrep -f "${SVC_DIR[$svc]}" &>/dev/null; then
      echo -e "    $label ${GREEN}running${NC}"
    else
      echo -e "    $label ${RED}stopped${NC}"
    fi
  fi
done
echo ""

# Credentials
echo -e "  ${BOLD}Credentials${NC}"
echo -e "    Client:  main.client@gmail.com / ClientSecret123!"
echo -e "    Admin:   app.admin@gmail.com / AdminSecret123!"
echo ""
