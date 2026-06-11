#!/bin/bash

# =============================================================================
# Seed local A2A payments — every lifecycle combination
# =============================================================================
# Populates `calytics-a2a-local-payments` with 9 fixture rows spanning every
# (status × session_status) combination that operational tooling needs to
# render. Designed for the calytics-fe `/a2a-payment` view + the
# `GET /clients/:clientId/a2a/payments` endpoint in calytics-be-admin.
#
# Idempotent: every row uses a deterministic `payment_id` prefixed with
# `seed-a2a-` so re-running deletes-then-puts the same rows.
#
# Usage:
#   cal seed a2a-payments
#
# Environment variables (optional):
#   AWS_ENDPOINT_URL          LocalStack endpoint (default: http://localhost:4566)
#   AWS_REGION                (default: eu-central-1)
#   PAYMENTS_TABLE_NAME       (default: calytics-a2a-local-payments)
#   SEED_A2A_CLIENT_ID        client_id used on every row (default: main local client)
# =============================================================================

set -euo pipefail

export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"
export AWS_PAGER=""

PAYMENTS_TABLE="${PAYMENTS_TABLE_NAME:-calytics-a2a-local-payments}"
CLIENT_ID="${SEED_A2A_CLIENT_ID:-9dea5b82-8e69-4039-840d-26d82ff7f257}"

# Colors (no-op if unset, e.g. when sourced standalone)
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_info()    { echo -e "${CYAN}ℹ${NC}  $1"; }
print_success() { echo -e "${GREEN}✓${NC}  $1"; }
print_warn()    { echo -e "${YELLOW}!${NC}  $1"; }

# Verify the table exists before doing anything destructive
if ! aws --endpoint-url "$AWS_ENDPOINT_URL" --region "$AWS_REGION" \
        dynamodb describe-table --table-name "$PAYMENTS_TABLE" >/dev/null 2>&1; then
  print_warn "Table $PAYMENTS_TABLE not found — run 'cal seed a2a-tables' first."
  exit 1
fi

# Epoch ms from epoch seconds — `date +%s%3N` is GNU-only (breaks on macOS BSD date)
NOW_MS="$(($(date +%s) * 1000))"
HOUR_MS=$((60 * 60 * 1000))
DAY_MS=$((24 * HOUR_MS))

# Time anchors: rows are spread across the last few days so the FE table
# default sort (transaction_date desc) renders a believable timeline.
declare -A T=(
    [now]="$NOW_MS"
    [5min_ago]=$((NOW_MS - 5 * 60 * 1000))
    [30min_ago]=$((NOW_MS - 30 * 60 * 1000))
    [2h_ago]=$((NOW_MS - 2 * HOUR_MS))
    [6h_ago]=$((NOW_MS - 6 * HOUR_MS))
    [1d_ago]=$((NOW_MS - DAY_MS))
    [2d_ago]=$((NOW_MS - 2 * DAY_MS))
    [3d_ago]=$((NOW_MS - 3 * DAY_MS))
    [5d_ago]=$((NOW_MS - 5 * DAY_MS))
)

# Each row models one operational scenario. Format:
#   payment_id|tenant_id|status|session_status|amount|finalized|webhook_received|callback_sent|callback_delivered|created_at_key|sender_name|sender_iban|recipient_name|recipient_iban|purpose|correlation_id
ROWS=(
    "seed-a2a-001|tenant-demo|SUCCESSFUL|COMPLETED|42.50|true|true|true|true|6h_ago|Alice Andersen|DE60500105175448413261|Calytics GmbH|DE04720500000252868930|Order #1001 — happy path|order-1001"
    "seed-a2a-002|tenant-demo|SUCCESSFUL|COMPLETED|199.00|true|true|true|false|2h_ago|Bob Brunner|DE89370400440532013000|Calytics GmbH|DE04720500000252868930|Order #1002 — webhook stuck mid-delivery|order-1002"
    "seed-a2a-003|tenant-demo|OPEN|NOT_YET_OPENED|2.50|false|false|false|false|now|Cedric Albeke|DE60500105175448413261|FOXPAY UG|DE74100500000191445100|Premium key — link sent, not opened yet|order-1003"
    "seed-a2a-004|tenant-demo|OPEN|IN_PROGRESS|74.99|false|false|false|false|5min_ago|Diana Diaz|DE14100500001664735239|Calytics GmbH|DE04720500000252868930|Order #1004 — customer on bank webform|order-1004"
    "seed-a2a-005|tenant-demo|NOT_SUCCESSFUL|COMPLETED_WITH_ERROR|330.00|true|true|true|true|1d_ago|Erik Eriksen|DE89370400440532013001|Calytics GmbH|DE04720500000252868930|Order #1005 — bank rejected|order-1005"
    "seed-a2a-006|tenant-demo|DISCARDED|ABORTED|18.00|true|true|true|true|2d_ago|Frieda Fischer|DE60500105175448413261|Calytics GmbH|DE04720500000252868930|Order #1006 — customer cancelled|order-1006"
    "seed-a2a-007|tenant-demo|DISCARDED|EXPIRED|1500.00|true|false|true|true|3d_ago|Gunther Gross|DE89370400440532013002|Calytics GmbH|DE04720500000252868930|Order #1007 — session expired|order-1007"
    "seed-a2a-008|tenant-premium|SUCCESSFUL|COMPLETED|9.99|true|true|true|true|30min_ago|Hannah Huber|DE14100500001664735239|Calytics GmbH|DE04720500000252868930|Subscription month #5|sub-2026-05-09"
    "seed-a2a-009|tenant-premium|OPEN|IN_PROGRESS|49.00|false|false|false|false|2h_ago|Ivan Ivanov|DE60500105175448413261|Calytics GmbH|DE04720500000252868930|Premium upgrade — in flight|sub-2026-05-09-upg"
)

print_info "Reseeding ${#ROWS[@]} A2A payment fixture rows in $PAYMENTS_TABLE for client $CLIENT_ID"

# ---------- delete-then-put for idempotency ----------
for row in "${ROWS[@]}"; do
    payment_id="$(echo "$row" | awk -F'|' '{print $1}')"
    aws --endpoint-url "$AWS_ENDPOINT_URL" --region "$AWS_REGION" \
        dynamodb delete-item --table-name "$PAYMENTS_TABLE" \
        --key "{\"payment_id\": {\"S\": \"$payment_id\"}}" >/dev/null 2>&1 || true
done

put_row() {
    local payment_id="$1"
    local tenant_id="$2"
    local status="$3"
    local session_status="$4"
    local amount="$5"
    local finalized="$6"
    local webhook_received="$7"
    local callback_sent="$8"
    local callback_delivered="$9"
    local created_at="${10}"
    local sender_name="${11}"
    local sender_iban="${12}"
    local recipient_name="${13}"
    local recipient_iban="${14}"
    local purpose="${15}"
    local correlation_id="${16}"

    local tenant_composite_key="${CLIENT_ID}#${tenant_id}"
    # Sessions expire 30min after creation in calytics-a2a; mirror that.
    local expires_at=$((created_at + 30 * 60 * 1000))
    local vendor_session_id="webform-${payment_id}"
    # Bogus webform URL — clickable in the detail dialog, leads nowhere harmful.
    local vendor_session_url="https://webform-sandbox.finapi.io/wf/${vendor_session_id}"

    cat > /tmp/a2a-seed-item.json <<JSON
{
  "payment_id":            {"S": "$payment_id"},
  "client_id":             {"S": "$CLIENT_ID"},
  "tenant_id":             {"S": "$tenant_id"},
  "tenant_composite_key":  {"S": "$tenant_composite_key"},
  "amount":                {"N": "$amount"},
  "currency":              {"S": "EUR"},
  "status":                {"S": "$status"},
  "session_status":        {"S": "$session_status"},
  "correlation_id":        {"S": "$correlation_id"},
  "purpose":               {"S": "$purpose"},
  "sender":                {"M": {"name": {"S": "$sender_name"}, "iban": {"S": "$sender_iban"}}},
  "recipient":             {"M": {"name": {"S": "$recipient_name"}, "iban": {"S": "$recipient_iban"}}},
  "sender_iban":           {"S": "$sender_iban"},
  "recipient_iban":        {"S": "$recipient_iban"},
  "vendor_name":           {"S": "finapi"},
  "vendor_session_id":     {"S": "$vendor_session_id"},
  "vendor_session_url":    {"S": "$vendor_session_url"},
  "finalized":             {"BOOL": $finalized},
  "webhook_received":      {"BOOL": $webhook_received},
  "callback_sent":         {"BOOL": $callback_sent},
  "callback_delivered":    {"BOOL": $callback_delivered},
  "created_at":            {"N": "$created_at"},
  "updated_at":            {"N": "$created_at"},
  "expires_at":            {"N": "$expires_at"}
}
JSON

    aws --endpoint-url "$AWS_ENDPOINT_URL" --region "$AWS_REGION" \
        dynamodb put-item --table-name "$PAYMENTS_TABLE" \
        --item file:///tmp/a2a-seed-item.json >/dev/null
}

for row in "${ROWS[@]}"; do
    IFS='|' read -r payment_id tenant_id status session_status amount finalized webhook_received callback_sent callback_delivered created_at_key sender_name sender_iban recipient_name recipient_iban purpose correlation_id <<< "$row"
    created_at="${T[$created_at_key]}"
    put_row "$payment_id" "$tenant_id" "$status" "$session_status" "$amount" \
            "$finalized" "$webhook_received" "$callback_sent" "$callback_delivered" \
            "$created_at" "$sender_name" "$sender_iban" \
            "$recipient_name" "$recipient_iban" "$purpose" "$correlation_id"
    print_info "  • $payment_id  $status / $session_status  €$amount"
done

rm -f /tmp/a2a-seed-item.json

print_success "$PAYMENTS_TABLE reseeded with ${#ROWS[@]} lifecycle-coverage rows."
