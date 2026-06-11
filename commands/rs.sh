#!/bin/bash
# cal rs <subcommand>
# Risk scoring tools.
#
# Subcommands:
#   cal rs stream <env> [flags]   Subscribe to remote DDB Stream → score locally
#   cal rs api                    Run local HTTP API (query endpoints) on :$RS_API_PORT
#
# Stream flags:
#   --source dg|a2a|all           Which stream (default: dg)
#   --history                     Read from oldest available (TRIM_HORIZON)
#
# Examples:
#   cal rs stream dev                  DG verifications, live (LATEST)
#   cal rs stream dev --history        From oldest available records
#   cal rs stream sandbox              DG verifications on sandbox
#   cal rs stream dev --source a2a     A2A payments stream
#   cal rs stream dev --source all     Both DG + A2A streams (parallel)
#   cal rs api                         Boot local query API (used by be-admin SDK)
#
# Prerequisites:
#   - AWS credentials (aws sso login or ~/.aws/credentials)  [stream only]
#   - LocalStack running (cal start infra)
#   - RS tables created (cal migrate dynamo)

subcmd="${1:-}"
shift 2>/dev/null || true
[ -z "$subcmd" ] && fail "Usage: cal rs <stream|api>"

case "$subcmd" in
  stream|api) ;; # handled below
  *) fail "Unknown subcommand: $subcmd (available: stream, api)" ;;
esac

# ═══════════════════════════════════════════════════════════════════════════
# cal rs api — local HTTP API for query endpoints (getScore, batch, history, reputation)
# ═══════════════════════════════════════════════════════════════════════════

if [ "$subcmd" = "api" ]; then
  phase "Risk Scoring local API"

  rs_dir="$(svc_path rs)"
  [ ! -d "$rs_dir" ] && fail "Risk scoring repo not found: $rs_dir"

  info "Checking LocalStack..."
  container_is_running "$INFRA_LOCALSTACK_CONTAINER" || \
    fail "LocalStack not running. Start with: cal start infra"
  ok "LocalStack running"

  info "Checking RS tables..."
  rs_tables_missing=false
  for table in "${RS_LOCAL_TABLES[@]}"; do
    AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
      aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb describe-table \
      --table-name "$table" --region "$AWS_REGION" &>/dev/null \
      || rs_tables_missing=true
  done
  if [ "$rs_tables_missing" = true ]; then
    info "RS tables missing — creating via migrate dynamo..."
    run_cmd migrate dynamo
    for table in "${RS_LOCAL_TABLES[@]}"; do
      AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
        aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb describe-table \
        --table-name "$table" --region "$AWS_REGION" &>/dev/null \
        || fail "Missing table after migrate: $table"
    done
  fi
  ok "RS tables present"

  # Free port if busy
  port_is_busy "$RS_API_PORT" && { warn "Port $RS_API_PORT busy — killing"; kill_port "$RS_API_PORT"; }

  # Env for the handlers — they talk to LocalStack
  export AWS_ENDPOINT_URL="$LOCALSTACK_ENDPOINT"
  export AWS_ACCESS_KEY_ID=test
  export AWS_SECRET_ACCESS_KEY=test
  export AWS_REGION="$AWS_REGION"
  export RISK_SCORING_IBAN_REPUTATION_TABLE_NAME="$TABLE_RS_IBAN_REPUTATION"
  export RISK_SCORING_CURRENT_SCORES_TABLE_NAME="$TABLE_RS_CURRENT_SCORES"
  export RISK_SCORING_SCORE_HISTORY_TABLE_NAME="$TABLE_RS_SCORE_HISTORY"
  export RISK_SCORING_VELOCITY_TABLE_NAME="$TABLE_RS_VELOCITY"
  export STAGE="$STAGE"
  export PORT="$RS_API_PORT"

  info "Starting RS API on :$RS_API_PORT — Ctrl+C to stop"
  exec bash -c "cd '$rs_dir' && npm run --silent api:local"
fi

# ═══════════════════════════════════════════════════════════════════════════
# cal rs stream <env> [--source dg|a2a|all] [--history]
# ═══════════════════════════════════════════════════════════════════════════

env=""
source_type="dg"
mode="LATEST"

for arg in "$@"; do
  case "$arg" in
    dev|development) env="dev" ;;
    sandbox)         env="sandbox" ;;
    --source)        : ;; # value handled by positional dg|a2a|all
    --source=*)      source_type="${arg#--source=}" ;;
    --history)       mode="TRIM_HORIZON" ;;
    dg|a2a|all)      source_type="$arg" ;;
    *)               fail "Unknown argument: $arg" ;;
  esac
done

[ -z "$env" ] && fail "Usage: cal rs stream <dev|sandbox> [--source dg|a2a|all] [--history]"

case "$source_type" in
  dg|a2a|all) ;;
  *) fail "Invalid source: $source_type (use: dg, a2a, all)" ;;
esac

# ── Preflight checks ───────────────────────────────────────────────────────

# Stream talks to real AWS — clear LocalStack overrides from defaults.sh
unset AWS_ENDPOINT_URL
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY

phase "Stream subscriber ($env)"

# 1. AWS credentials
info "Checking AWS credentials..."
aws_identity=$(aws sts get-caller-identity --region "$AWS_REGION" --output json 2>&1) || \
  fail "AWS credentials not configured. Run: aws sso login"
aws_user=$(echo "$aws_identity" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Arn','').split('/')[-1])" 2>/dev/null || echo "unknown")
aws_account=$(echo "$aws_identity" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Account',''))" 2>/dev/null || echo "unknown")
ok "AWS credentials OK ($aws_user @ $aws_account)"

# 2. LocalStack
info "Checking LocalStack..."
container_is_running "$INFRA_LOCALSTACK_CONTAINER" || \
  fail "LocalStack not running. Start with: cal start infra"
ok "LocalStack running"

# 3. RS tables in LocalStack
info "Checking RS tables..."
missing=0
for table in "${RS_LOCAL_TABLES[@]}"; do
  if ! AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
       aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb describe-table \
       --table-name "$table" --region "$AWS_REGION" &>/dev/null; then
    warn "Missing table: $table"
    missing=$((missing + 1))
  fi
done
[ "$missing" -gt 0 ] && fail "$missing RS table(s) missing. Run: cal migrate dynamo"
ok "RS tables present (${#RS_LOCAL_TABLES[@]}/${#RS_LOCAL_TABLES[@]})"

# ── Resolve stream ARN(s) ──────────────────────────────────────────────────

resolve_stream_arn() {
  local table_name="$1"
  local arn
  arn=$(aws dynamodb describe-table \
    --table-name "$table_name" \
    --region "$AWS_REGION" \
    --query 'Table.LatestStreamArn' \
    --output text 2>/dev/null)
  if [ -z "$arn" ] || [ "$arn" = "None" ] || [ "$arn" = "null" ]; then
    return 1
  fi
  echo "$arn"
}

rs_dir="$(svc_path rs)"
[ ! -d "$rs_dir" ] && fail "Risk scoring repo not found: $rs_dir"

declare -a sources=()
declare -a arns=()

if [ "$source_type" = "dg" ] || [ "$source_type" = "all" ]; then
  dg_table="${STREAM_VERIFICATIONS_TABLE[$env]}"
  info "Resolving DG stream ARN ($dg_table)..."
  dg_arn=$(resolve_stream_arn "$dg_table") || fail "Stream not found on $dg_table. Is DDB Streams enabled?"
  ok "DG stream: ${dg_arn##*/stream/}"
  sources+=("dg")
  arns+=("$dg_arn")
fi

if [ "$source_type" = "a2a" ] || [ "$source_type" = "all" ]; then
  a2a_table="${STREAM_PAYMENTS_TABLE[$env]}"
  info "Resolving A2A stream ARN ($a2a_table)..."
  a2a_arn=$(resolve_stream_arn "$a2a_table") || fail "Stream not found on $a2a_table. Is DDB Streams enabled?"
  ok "A2A stream: ${a2a_arn##*/stream/}"
  sources+=("a2a")
  arns+=("$a2a_arn")
fi

# ── Launch subscriber(s) ───────────────────────────────────────────────────

mode_label="live"
[ "$mode" = "TRIM_HORIZON" ] && mode_label="history"

echo ""
info "Starting ${#sources[@]} subscriber(s) in ${BOLD}${mode_label}${NC} mode. Press Ctrl+C to stop."
echo ""

export LOCALSTACK_ENDPOINT="$LOCALSTACK_ENDPOINT"
export RS_TABLE_REPUTATION="$TABLE_RS_IBAN_REPUTATION"
export RS_TABLE_SCORES="$TABLE_RS_CURRENT_SCORES"
export RS_TABLE_HISTORY="$TABLE_RS_SCORE_HISTORY"
export RS_TABLE_VELOCITY="$TABLE_RS_VELOCITY"
export STREAM_MODE="$mode"

unset AWS_ENDPOINT_URL
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY

if [ "${#sources[@]}" -eq 1 ]; then
  export STREAM_ARN="${arns[0]}"
  export STREAM_SOURCE="${sources[0]}"
  exec npx tsx "$rs_dir/scripts/stream-subscriber.ts"
else
  pids=()
  for i in "${!sources[@]}"; do
    STREAM_ARN="${arns[$i]}" STREAM_SOURCE="${sources[$i]}" \
      npx tsx "$rs_dir/scripts/stream-subscriber.ts" &
    pids+=($!)
  done
  trap 'for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; wait; exit 0' INT TERM
  wait
fi
