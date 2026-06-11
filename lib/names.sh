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
  [cp]=3045
  [rs]=0
  [rs-api]=4002
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
  [cp]=calytics-cross-product
  [rs]=calytics-risk-scoring
  [rs-api]=calytics-risk-scoring
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
  [cp]="npm run offline:local"
  [rs]="npm run stream"
  [rs-api]="npm run api:local"
)

# ── Log files ────────────────────────────────────────────────────
declare -A SVC_LOG=(
  [be]="$LOG_DIR/calytics-be.log"
  [a2a]="$LOG_DIR/calytics-a2a.log"
  [cp]="$LOG_DIR/calytics-cross-product.log"
  [rs]="$LOG_DIR/calytics-risk-scoring.log"
  [rs-api]="$LOG_DIR/calytics-risk-scoring-api.log"
)

# ── Human-readable labels ────────────────────────────────────────
declare -A SVC_LABEL=(
  [be]="calytics-be"
  [a2a]="calytics-a2a"
  [cp]="calytics-cross-product"
  [rs]="calytics-risk-scoring"
  [rs-api]="calytics-risk-scoring API"
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
  [cp]="http://localhost:${SVC_PORT[cp]}"
  [rs]=""
  [rs-api]="http://localhost:${SVC_PORT[rs-api]}"
  [admin]="http://localhost:${SVC_PORT[admin]}"
  [fe]="http://$LOCAL_IP:${SVC_PORT[fe]}"
  [docs]="http://localhost:${SVC_PORT[docs]}"
  [dynamo-gui]="http://localhost:${SVC_PORT[dynamo-gui]}"
  [webhooks]="http://localhost:${SVC_PORT[webhooks]}"
)

# ── Service categorization ───────────────────────────────────────
# `cp` (calytics-cross-product) is the multi-product matcher / dispute-recognition
# orchestrator: Payment Reconciliation lives here, Dispute Recognition lives here.
# Producers (be, a2a) publish to its SQS queue; this lambda consumes + processes.
SVC_PROCESS_LIST=(be a2a cp rs rs-api)
SVC_DOCKER_LIST=(admin fe docs dynamo-gui webhooks)
SVC_ALL_LIST=(be a2a cp rs rs-api admin fe docs dynamo-gui webhooks)
SVC_INFRA_DEPENDENT=(be a2a cp rs rs-api admin fe)
SVC_INDEPENDENT=(docs dynamo-gui webhooks)

# Services whose start command invokes Serverless Framework v4, which phones
# home to api.serverless.com on every run. `start_process_service` uses this
# to auto-retry when the license-check fetch fails with ETIMEDOUT.
SVC_USES_SERVERLESS=(be a2a cp rs)

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
QUEUE_BE_DG_HOUSEKEEPING="calytics-be-${STAGE}-dg-housekeeping"
QUEUE_BE_DG_HOUSEKEEPING_DLQ="calytics-be-${STAGE}-dg-housekeeping-dlq"
QUEUE_BE_DEAD_LETTER="calytics-be-${STAGE}-dead-letter.fifo"
QUEUE_BE_JOBS="calytics-be-${STAGE}-jobs"
QUEUE_A2A_DATA_ENRICHMENT="calytics-a2a-${STAGE}-data-enrichment.fifo"
QUEUE_A2A_DATA_ENRICHMENT_DLQ="calytics-a2a-${STAGE}-data-enrichment-dlq.fifo"

# Cross-product (Payment Reconciliation + Dispute Recognition transporter).
# Producers (be, a2a) publish here; cross-product Lambda consumes via SQS event source.
QUEUE_CROSS_PRODUCT_TRANSPORTER="cross-product-transporter.fifo"
QUEUE_CROSS_PRODUCT_TRANSPORTER_DLQ="cross-product-transporter-dlq.fifo"

# Cross-product DDB tables. In production these live in an external infra repo
# (cross-product reads them via `data "aws_dynamodb_table"`); LocalStack is
# seeded from `seeders/cross-product-tables.sh` for parity.
TABLE_CROSS_PRODUCT_WORKER_TASKS="cross-product-${STAGE}-worker-tasks"
TABLE_CROSS_PRODUCT_RETURNS_LOG="cross-product-${STAGE}-returns-log"

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
# Local webhook tester: ghcr.io/tarampampam/webhook-tester:2 on :8090.
# Started with `--auto-create-sessions`, so any inbound request to /{uuid}
# materializes the session if it doesn't already exist. UUIDs are pinned per
# product so callback URLs in seeded webhooks/Postman/docs are stable across
# restarts, fresh volumes, and different machines.
export WEBHOOK_IMAGE="ghcr.io/tarampampam/webhook-tester:2"
export WEBHOOK_BASE_URL="http://localhost:${SVC_PORT[webhooks]}"

# Product labels for webhook sessions
WEBHOOK_PRODUCTS=(dg oc a2a)
declare -A WEBHOOK_PRODUCT_LABEL=( [dg]="DebitGuard" [oc]="OwnershipCheck" [a2a]="A2A + CC" )

export WEBHOOK_SESSION_DG="a0937803-8760-4282-83ce-873ca2d1d78c"
export WEBHOOK_SESSION_OC="844af3bb-3fda-45df-a823-d4ef235309dc"
export WEBHOOK_SESSION_A2A="f5e27a02-ad19-4641-8e56-8bc9f4d33cfb"

export WEBHOOK_URL_DG="${WEBHOOK_BASE_URL}/${WEBHOOK_SESSION_DG}"
export WEBHOOK_URL_OC="${WEBHOOK_BASE_URL}/${WEBHOOK_SESSION_OC}"
export WEBHOOK_URL_A2A="${WEBHOOK_BASE_URL}/${WEBHOOK_SESSION_A2A}"
export WEBHOOK_UI_DG="${WEBHOOK_BASE_URL}/s/${WEBHOOK_SESSION_DG}"
export WEBHOOK_UI_OC="${WEBHOOK_BASE_URL}/s/${WEBHOOK_SESSION_OC}"
export WEBHOOK_UI_A2A="${WEBHOOK_BASE_URL}/s/${WEBHOOK_SESSION_A2A}"

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
SEEDER_A2A_PAYMENTS="a2a-payments"
SEEDER_CROSS_PRODUCT_TABLES="cross-product-tables"

# Ordered list for `cal seed all` — webhooks excluded (auto-seeded by cal start webhooks)
SEEDER_ALL_LIST=(
  "$SEEDER_SECRETS"
  "$SEEDER_QUEUES"
  "$SEEDER_SES"
  "$SEEDER_CLIENT"
  "$SEEDER_PLANS"
  "$SEEDER_API_KEYS"
  "$SEEDER_CROSS_PRODUCT_TABLES"
  "$SEEDER_A2A_PAYMENTS"
)

# ── Stream subscriber (remote env → local scoring) ──────────────
# Table name patterns per remote environment (for dynamic ARN lookup)
declare -A STREAM_VERIFICATIONS_TABLE=(
  [dev]="calytics-be-development-verifications"
  [sandbox]="calytics-be-sandbox-verifications"
)
declare -A STREAM_PAYMENTS_TABLE=(
  [dev]="calytics-a2a-development-payments"
  [sandbox]="calytics-a2a-sandbox-payments"
)

# RS LocalStack table names (for preflight check)
RS_LOCAL_TABLES=(
  "$TABLE_RS_IBAN_REPUTATION"
  "$TABLE_RS_CURRENT_SCORES"
  "$TABLE_RS_SCORE_HISTORY"
  "$TABLE_RS_VELOCITY"
)

# RS local HTTP API (query endpoints) — spun up by `cal rs api`
RS_API_PORT=4002
RS_API_URL="http://localhost:${RS_API_PORT}"

# ── Canary resources (checked after LocalStack restart) ──────────
# Kept as a scalar for backwards compatibility; the list below is authoritative.
CANARY_SQS_QUEUE="$QUEUE_BE_DATA_ENRICHMENT"
# All SQS queues whose absence should trigger a re-seed. Include one per service
# that consumes its own queues via serverless-offline-sqs so LocalStack state loss
# is caught for any service, not just BE.
CANARY_SQS_QUEUES=(
  "$QUEUE_BE_DATA_ENRICHMENT"
  "$QUEUE_BE_DG_HOUSEKEEPING"
  "$QUEUE_A2A_DATA_ENRICHMENT"
  "$QUEUE_CROSS_PRODUCT_TRANSPORTER"
)
CANARY_SECRET_ID="$SECRET_API_KEY_ENCRYPTION"
