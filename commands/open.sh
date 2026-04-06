#!/bin/bash
# cal open <service> [product]
# Open a service URL in the default browser.
#
# Examples:
#   cal open fe                 Open frontend
#   cal open admin              Open admin API
#   cal open docs               Open API docs
#   cal open webhooks           Open webhook dashboard (shows all sessions)
#   cal open webhooks dg        Open DebitGuard webhook session
#   cal open webhooks oc        Open OwnershipCheck webhook session
#   cal open webhooks a2a       Open A2A + CC webhook session
#   cal open webhooks cc        Same as a2a

target="${1:-}"
product="${2:-}"
[ -z "$target" ] && fail "Usage: cal open <service> [product]"

svc=$(svc_resolve "$target") || fail "Unknown service: $target"
port="${SVC_PORT[$svc]}"
label="${SVC_LABEL[$svc]}"

[ "$port" -eq 0 ] && fail "$label has no HTTP port"

url="http://localhost:$port"

# Detect browser opener
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

_open() {
  if [ -n "$opener" ]; then
    info "Opening → $1"
    $opener "$1" 2>/dev/null &
  else
    info "$1"
    warn "No browser opener found — copy the URL manually"
  fi
}

# Webhooks: resolve product to session URL
if [ "$svc" = "webhooks" ]; then
  case "$product" in
    dg|debit-guard)
      _open "$url/#/$WEBHOOK_SESSION_DG"
      ;;
    oc|ownership-check)
      _open "$url/#/$WEBHOOK_SESSION_OC"
      ;;
    a2a|cc|collect)
      _open "$url/#/$WEBHOOK_SESSION_A2A"
      ;;
    "")
      # No product — show all + open dashboard
      echo ""
      echo -e "  ${BOLD}Webhook Tester Sessions${NC}"
      echo ""
      echo -e "  ${CYAN}DebitGuard:${NC}       $url/#/$WEBHOOK_SESSION_DG"
      echo -e "  ${CYAN}OwnershipCheck:${NC}   $url/#/$WEBHOOK_SESSION_OC"
      echo -e "  ${CYAN}A2A + CC:${NC}         $url/#/$WEBHOOK_SESSION_A2A"
      echo ""
      _open "$url"
      ;;
    *)
      fail "Unknown product: $product (try: dg, oc, a2a, cc)"
      ;;
  esac
  exit 0
fi

_open "$url"
