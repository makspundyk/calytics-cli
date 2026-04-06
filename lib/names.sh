#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# NAMES REGISTRY — Single source of truth for every name in the system
#
# Every queue, secret, table, container, port, folder, file, credential,
# and API key is declared HERE. Nothing else may contain raw strings.
#
# To add/rename/remove anything: change it here. Done.
# ═══════════════════════════════════════════════════════════════════

# ── Stage ────────────────────────────────────────────────────────
STAGE="${STAGE:-local}"

# ── Network ──────────────────────────────────────────────────────
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
LOCALSTACK_ENDPOINT="http://localhost:4566"

# ── Infrastructure containers ────────────────────────────────────
INFRA_LOCALSTACK_CONTAINER="localstack_main"
INFRA_POSTGRES_CONTAINER="calytics_postgres"
INFRA_LOCALSTACK_PORT=4566
INFRA_POSTGRES_PORT=5432

# ── Log directory ────────────────────────────────────────────────
LOG_DIR="/tmp"

# ── Docker compose ───────────────────────────────────────────────
COMPOSE_PROJECT="calytics"

# ── Service ports ────────────────────────────────────────────────
declare -A SVC_PORT=(
  [be]=3333
  [a2a]=3000
  [rs]=0
  [admin]=9000
  [fe]=5000
  [docs]=8080
  [dynamo-gui]=8001
  [webhooks]=8090
)

# ── Service directories (relative to project root) ───────────────
declare -A SVC_DIR=(
  [be]=calytics-be
  [a2a]=calytics-a2a
  [rs]=calytics-risk-scoring
  [admin]=calytics-be-admin
  [fe]=calytics-fe
  [docs]=client-openapi-docs
)

# ── Docker container names ───────────────────────────────────────
declare -A SVC_CONTAINER=(
  [admin]=calytics_be_admin
  [fe]=calytics_fe
  [docs]=calytics_docs
  [dynamo-gui]=dynamodb-gui
  [webhooks]=calytics-webhook-tester
)

# ── Start commands ───────────────────────────────────────────────
declare -A SVC_START=(
  [be]="npm run offline:local"
  [a2a]="npm run offline:local"
  [rs]="npm run stream:dev"
)

# ── Log files ────────────────────────────────────────────────────
declare -A SVC_LOG=(
  [be]="$LOG_DIR/calytics-be.log"
  [a2a]="$LOG_DIR/calytics-a2a.log"
  [rs]="$LOG_DIR/calytics-risk-scoring.log"
)

# ── Human-readable labels ────────────────────────────────────────
declare -A SVC_LABEL=(
  [be]="calytics-be"
  [a2a]="calytics-a2a"
  [rs]="calytics-risk-scoring"
  [admin]="calytics-be-admin"
  [fe]="calytics-fe"
  [docs]="API docs"
  [dynamo-gui]="DynamoDB GUI"
  [webhooks]="Webhook Tester"
)

# ── Service URLs ─────────────────────────────────────────────────
declare -A SVC_URL=(
  [be]="http://localhost:${SVC_PORT[be]}"
  [a2a]="http://localhost:${SVC_PORT[a2a]}"
  [rs]=""
  [admin]="http://localhost:${SVC_PORT[admin]}"
  [fe]="http://$LOCAL_IP:${SVC_PORT[fe]}"
  [docs]="http://localhost:${SVC_PORT[docs]}"
  [dynamo-gui]="http://localhost:${SVC_PORT[dynamo-gui]}"
  [webhooks]="http://localhost:${SVC_PORT[webhooks]}"
)

# ── Service categorization ───────────────────────────────────────
SVC_PROCESS_LIST=(be a2a rs)
SVC_DOCKER_LIST=(admin fe docs dynamo-gui webhooks)
SVC_ALL_LIST=(be a2a rs admin fe docs dynamo-gui webhooks)
SVC_INFRA_DEPENDENT=(be a2a rs admin fe)
SVC_INDEPENDENT=(docs dynamo-gui webhooks)

# ── DynamoDB table names ─────────────────────────────────────────
# BE tables
TABLE_IDEMPOTENCY="idempotency-be-${STAGE}-idempotency"
TABLE_TRANSACTIONS="calytics-be-${STAGE}-transactions"
TABLE_VERIFICATIONS="calytics-be-${STAGE}-verifications"
TABLE_VERIFICATION_EVENTS="calytics-be-${STAGE}-verification-event"
TABLE_VENDOR_DATA="calytics-be-${STAGE}-vendor-data"
TABLE_DISPUTED_TRANSACTIONS="calytics-shared-${STAGE}-disputed-transactions"
TABLE_AIS_CONNECTIONS="calytics-shared-${STAGE}-ais-connections"
TABLE_RECONCILABLE_TRANSACTIONS="calytics-shared-${STAGE}-reconcilable-transactions"
TABLE_TRANSACTION_CODES="calytics-a2a-${STAGE}-transaction-codes"
TABLE_FILE_UPLOADS="calytics-be-${STAGE}-file-upload-records"
TABLE_ALERTS="calytics-be-${STAGE}-alerts"

# A2A tables
TABLE_A2A_PAYMENTS="calytics-a2a-${STAGE}-payments"
TABLE_A2A_IDEMPOTENCY="calytics-a2a-${STAGE}-payments-idempotency"
TABLE_A2A_PAYMENT_TRANSACTIONS="calytics-a2a-payment-transactions"

# Calytics Collect tables
TABLE_CC_SESSIONS="calytics-cc-${STAGE}-sessions"
TABLE_CC_MANDATES="calytics-cc-${STAGE}-mandates"
TABLE_CC_AUDIT="calytics-cc-${STAGE}-audit-events"
TABLE_CC_WEBHOOK_EVENTS="calytics-cc-${STAGE}-webhook-events"
TABLE_CC_MANDATE_TRANSACTIONS="calytics-cc-${STAGE}-mandate-transactions"

# Risk Scoring tables
TABLE_RS_IBAN_REPUTATION="calytics-risk-scoring-${STAGE}-iban-reputation"
TABLE_RS_CURRENT_SCORES="calytics-risk-scoring-${STAGE}-current-scores"
TABLE_RS_SCORE_HISTORY="calytics-risk-scoring-${STAGE}-score-history"
TABLE_RS_VELOCITY="calytics-risk-scoring-${STAGE}-velocity"

# ── SQS queue names ──────────────────────────────────────────────
QUEUE_BE_DATA_ENRICHMENT="calytics-be-${STAGE}-data-enrichment.fifo"
QUEUE_BE_DATA_ENRICHMENT_DLQ="calytics-be-${STAGE}-data-enrichment-dlq.fifo"
QUEUE_BE_CLIENT_CALLBACK="calytics-be-${STAGE}-client-callback"
QUEUE_BE_CLIENT_CALLBACK_DLQ="calytics-be-${STAGE}-client-callback-dlq"
QUEUE_BE_DEAD_LETTER="calytics-be-${STAGE}-dead-letter.fifo"
QUEUE_BE_JOBS="calytics-be-${STAGE}-jobs"
QUEUE_A2A_DATA_ENRICHMENT="calytics-a2a-${STAGE}-data-enrichment.fifo"
QUEUE_A2A_DATA_ENRICHMENT_DLQ="calytics-a2a-${STAGE}-data-enrichment-dlq.fifo"

# ── Secrets Manager IDs ──────────────────────────────────────────
SECRET_API_KEY_ENCRYPTION="calytics-be-admin/api-key-encryption"
SECRET_WEBHOOK_ENCRYPTION="calytics-be-admin/webhook-encryption"
SECRET_UI_VALIDATOR="calytics/local/api-key/ui-validator"
SECRET_REVOLUT_CREDS="calytics/calytics-be/${STAGE}/revolut/credentials"
SECRET_REVOLUT_STATIC="calytics/calytics-be/${STAGE}/revolut/static-credentials"
SECRET_FINAPI_CREDS="calytics/calytics-be/${STAGE}/finapi/credentials"
SECRET_FINAPI_STATIC="calytics/calytics-be/${STAGE}/finapi/static-credentials"
SECRET_A2A_FINAPI_CREDS="calytics/a2a/${STAGE}/finapi/credentials"
SECRET_A2A_FINAPI_STATIC="calytics/a2a/${STAGE}/finapi/static-credentials"
SECRET_QONTO_CREDS="calytics/qonto/credentials"
SECRET_QONTO_STATIC="calytics/qonto/static-credentials"
SECRET_BRIGHT_DATA="calytics/local/bright-data/credentials"
SECRET_BRIGHT_DATA_PROD="calytics/prod/bright-data/credentials"

# ── Webhook Tester ────────────────────────────────────────────────
WEBHOOK_IMAGE="ghcr.io/tarampampam/webhook-tester:2"
WEBHOOK_DATA_DIR="/tmp/calytics-webhooks"
WEBHOOK_STATE_FILE="$WEBHOOK_DATA_DIR/.sessions.env"
WEBHOOK_BASE_URL="http://localhost:${SVC_PORT[webhooks]}"

# Product labels for webhook sessions
WEBHOOK_PRODUCTS=(dg oc a2a)
declare -A WEBHOOK_PRODUCT_LABEL=( [dg]="DebitGuard" [oc]="OwnershipCheck" [a2a]="A2A + CC" )

# Load session UUIDs from state file (created by `cal seed webhooks`)
# If file doesn't exist yet, variables are empty — seeder creates them.
WEBHOOK_SESSION_DG=""
WEBHOOK_SESSION_OC=""
WEBHOOK_SESSION_A2A=""
if [ -f "$WEBHOOK_STATE_FILE" ]; then
  source "$WEBHOOK_STATE_FILE"
fi

# Derived URLs (empty if sessions not created yet)
WEBHOOK_URL_DG="${WEBHOOK_SESSION_DG:+${WEBHOOK_BASE_URL}/${WEBHOOK_SESSION_DG}}"
WEBHOOK_URL_OC="${WEBHOOK_SESSION_OC:+${WEBHOOK_BASE_URL}/${WEBHOOK_SESSION_OC}}"
WEBHOOK_URL_A2A="${WEBHOOK_SESSION_A2A:+${WEBHOOK_BASE_URL}/${WEBHOOK_SESSION_A2A}}"
WEBHOOK_UI_DG="${WEBHOOK_SESSION_DG:+${WEBHOOK_BASE_URL}/s/${WEBHOOK_SESSION_DG}}"
WEBHOOK_UI_OC="${WEBHOOK_SESSION_OC:+${WEBHOOK_BASE_URL}/s/${WEBHOOK_SESSION_OC}}"
WEBHOOK_UI_A2A="${WEBHOOK_SESSION_A2A:+${WEBHOOK_BASE_URL}/s/${WEBHOOK_SESSION_A2A}}"

# ── S3 bucket names ──────────────────────────────────────────────
S3_ADMIN_BUCKET="calytics-be-${STAGE}-admin"
S3_MANDATE_PDF="calytics-cc-${STAGE}-pdf"

# ── API keys (local dev) ─────────────────────────────────────────
APIKEY_DEBIT_GUARD="ak_sand_21c0f785e49e88d7c7d5b6a8f19a2402bbb190e2198a6158a7aa30331aa0e2b2"
APIKEY_OWNERSHIP_CHECK="ak_sand_ff764a4e74ce9c8830c705c73ba57f911bbf4d81b3d63be427dc1641ae3bcb3a"
APIKEY_A2A="ak_sand_b0694c75fd1c374d264ae48cfb68469cff5d484257b785e0093f04f60ff7b51f"
APIKEY_CALYTICS_COLLECT="ak_sand_917986e01ffd95becf1cbf47cd28c04e02bbf48fbe1caa903389044c3a6d58c9"
APIKEY_SMART_SWITCH="ak_sand_bc35765b987aa342931123986cdf6d2e4eeeffd7d029ef19ca27a1b906f33d06"

# ── Credentials (display only) ───────────────────────────────────
CRED_CLIENT_EMAIL="main.client@gmail.com"
CRED_CLIENT_PASS="ClientSecret123!"
CRED_ADMIN_EMAIL="app.admin@gmail.com"
CRED_ADMIN_PASS="AdminSecret123!"

# ── Git author config ────────────────────────────────────────────
GIT_AUTHOR_NAME="Maksym Pundyk"
GIT_AUTHOR_EMAIL_COMPANY="m.pundyk@calytics.io"
GIT_AUTHOR_EMAIL_CLI="maksym.p@ideainyou.com"

# ── Seeder file names ────────────────────────────────────────────
SEEDER_SECRETS="secrets"
SEEDER_QUEUES="queues"
SEEDER_SES="ses"
SEEDER_CLIENT="client"
SEEDER_WEBHOOKS="webhooks"
SEEDER_PLANS="plans"
SEEDER_API_KEYS="api-keys"
SEEDER_A2A_TABLES="a2a-tables"

SEEDER_ALL_LIST=(
  "$SEEDER_SECRETS"
  "$SEEDER_QUEUES"
  "$SEEDER_SES"
  "$SEEDER_CLIENT"
  "$SEEDER_WEBHOOKS"
  "$SEEDER_PLANS"
  "$SEEDER_API_KEYS"
)

# ── Canary resources (checked after LocalStack restart) ──────────
CANARY_SQS_QUEUE="$QUEUE_BE_DATA_ENRICHMENT"
CANARY_SECRET_ID="$SECRET_API_KEY_ENCRYPTION"
