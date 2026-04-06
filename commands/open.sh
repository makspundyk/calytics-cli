#!/bin/bash
# cal open <service>
# Open a service URL in the default browser.
#
# Examples:
#   cal open fe           Open frontend (:5000)
#   cal open admin        Open admin API (:9000)
#   cal open docs         Open API docs (:8080)
#   cal open dynamo-gui   Open DynamoDB admin (:8001)
#   cal open be           Open banking API (:3333)

target="${1:-}"
[ -z "$target" ] && fail "Usage: cal open <service> (fe, admin, docs, dynamo-gui, be, a2a)"

svc=$(svc_resolve "$target") || fail "Unknown service: $target"
port="${SVC_PORT[$svc]}"
label="${SVC_LABEL[$svc]}"

[ "$port" -eq 0 ] && fail "$label has no HTTP port"

url="http://localhost:$port"

# Detect browser opener (WSL → Windows browser, Linux → xdg-open, Mac → open)
if command -v wslview &>/dev/null; then
  opener="wslview"
elif command -v xdg-open &>/dev/null; then
  opener="xdg-open"
elif command -v open &>/dev/null; then
  opener="open"
elif command -v explorer.exe &>/dev/null; then
  opener="explorer.exe"
else
  opener=""
fi

# Special handling for webhooks — show all session URLs
if [ "$svc" = "webhooks" ]; then
  echo ""
  echo -e "  ${BOLD}Webhook Tester Sessions${NC}"
  echo ""
  echo -e "  ${CYAN}DebitGuard:${NC}       $url/#/$WEBHOOK_SESSION_DG"
  echo -e "  ${CYAN}OwnershipCheck:${NC}   $url/#/$WEBHOOK_SESSION_OC"
  echo -e "  ${CYAN}A2A + CC:${NC}         $url/#/$WEBHOOK_SESSION_A2A"
  echo ""
  echo -e "  ${DIM}Dashboard:${NC}        $url"
  echo ""
  if [ -n "$opener" ]; then
    $opener "$url" 2>/dev/null &
  fi
  exit 0
fi

if [ -z "$opener" ]; then
  info "$label → $url"
  warn "No browser opener found — copy the URL manually"
  exit 0
fi

info "Opening $label → $url"
$opener "$url" 2>/dev/null &
