#!/bin/bash
# Service registry — single source of truth for all service metadata
# Every script uses these vars. Change here → changes everywhere.

# ── Infrastructure ───────────────────────────────────────────────
INFRA_LOCALSTACK_PORT=4566
INFRA_POSTGRES_PORT=5432
INFRA_LOCALSTACK_CONTAINER="localstack_main"
INFRA_POSTGRES_CONTAINER="calytics_postgres"

# ── Log directory ────────────────────────────────────────────────
LOG_DIR="/tmp"

# ── Ports ────────────────────────────────────────────────────────
declare -A SVC_PORT=(
  [be]=3333
  [a2a]=3000
  [rs]=0          # no HTTP port — stream subscriber
  [admin]=9000
  [fe]=5000
  [docs]=8080
  [dynamo-gui]=8001
)

# ── Project directories (relative to CAL_PROJECT) ────────────────
declare -A SVC_DIR=(
  [be]=calytics-be
  [a2a]=calytics-a2a
  [rs]=calytics-risk-scoring
  [admin]=calytics-be-admin
  [fe]=calytics-fe
  [docs]=client-openapi-docs
)

# ── Docker container names (docker-managed services) ─────────────
declare -A SVC_CONTAINER=(
  [admin]=calytics_be_admin
  [fe]=calytics_fe
  [docs]=calytics_docs
  [dynamo-gui]=dynamodb-gui
)

# ── Start commands (process-managed services) ────────────────────
declare -A SVC_START=(
  [be]="npm run offline:local"
  [a2a]="npm run offline:local"
  [rs]="npm run stream:dev"
)

# ── Log files (derived from LOG_DIR + SVC_DIR) ───────────────────
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
)

# ── Categorization ───────────────────────────────────────────────
SVC_PROCESS_LIST=(be a2a rs)                # started as background Node processes
SVC_DOCKER_LIST=(admin fe docs dynamo-gui)  # started as Docker containers
SVC_ALL_LIST=(be a2a rs admin fe docs dynamo-gui)
SVC_INFRA_DEPENDENT=(be a2a rs admin fe)    # need LocalStack + Postgres to run
SVC_INDEPENDENT=(docs dynamo-gui)           # can run without infra

# ── Git author config ────────────────────────────────────────────
GIT_AUTHOR_NAME="Maksym Pundyk"
GIT_AUTHOR_EMAIL_COMPANY="m.pundyk@calytics.io"
GIT_AUTHOR_EMAIL_CLI="maksym.p@ideainyou.com"

# ── Credentials (display only) ───────────────────────────────────
CRED_CLIENT_EMAIL="main.client@gmail.com"
CRED_CLIENT_PASS="ClientSecret123!"
CRED_ADMIN_EMAIL="app.admin@gmail.com"
CRED_ADMIN_PASS="AdminSecret123!"

# ── Helper: resolve alias → canonical name ───────────────────────
svc_resolve() {
  case "$1" in
    be|debit-guard|dg|backend) echo "be" ;;
    a2a)                       echo "a2a" ;;
    rs|risk|risk-scoring)      echo "rs" ;;
    admin|be-admin)            echo "admin" ;;
    fe|frontend)               echo "fe" ;;
    docs)                      echo "docs" ;;
    dynamo-gui|dynamo|dg-ui)   echo "dynamo-gui" ;;
    *) return 1 ;;
  esac
}

# ── Helper: service type checks ──────────────────────────────────
svc_is_docker()  { [[ -n "${SVC_CONTAINER[$1]:-}" ]]; }
svc_is_process() { [[ -n "${SVC_START[$1]:-}" ]]; }

# ── Helper: get full path to service directory ───────────────────
svc_path() { echo "$CAL_PROJECT/${SVC_DIR[$1]}"; }
