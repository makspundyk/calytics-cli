#!/bin/bash
# Default environment variables for local development
# Sourced by cal.sh before every command

export AWS_REGION="${AWS_REGION:-eu-central-1}"
export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-000000000000}"

export POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-register}"
export POSTGRES_DB="${POSTGRES_DB:-calytics-admin}"

export SERVICE_NAME="${SERVICE_NAME:-calytics-be}"
export STAGE="${STAGE:-local}"

# Risk-scoring handler env (consumed by scripts/local-api.ts and the Lambda handlers).
# Names mirror the production env injected by Terraform; values are derived from
# TABLE_RS_* in lib/names.sh so renames propagate from a single source of truth.
export RISK_SCORING_IBAN_REPUTATION_TABLE_NAME="${RISK_SCORING_IBAN_REPUTATION_TABLE_NAME:-$TABLE_RS_IBAN_REPUTATION}"
export RISK_SCORING_CURRENT_SCORES_TABLE_NAME="${RISK_SCORING_CURRENT_SCORES_TABLE_NAME:-$TABLE_RS_CURRENT_SCORES}"
export RISK_SCORING_SCORE_HISTORY_TABLE_NAME="${RISK_SCORING_SCORE_HISTORY_TABLE_NAME:-$TABLE_RS_SCORE_HISTORY}"
export RISK_SCORING_VELOCITY_TABLE_NAME="${RISK_SCORING_VELOCITY_TABLE_NAME:-$TABLE_RS_VELOCITY}"

export BE_ADMIN_DIR="${BE_ADMIN_DIR:-$CAL_PROJECT/calytics-be-admin}"
export SHARED_MODULES_DIR="${SHARED_MODULES_DIR:-$CAL_PROJECT/calytics-shared-modules}"

# WSL2 resolves AAAA records via the Windows-side nameserver and frequently stalls
# on IPv6 before falling back to IPv4. Node's fetch (used by Serverless Framework v4
# for its license check) hits this hard, producing `ETIMEDOUT` against api.serverless.com
# even when curl works fine. Forcing IPv4-first preserves normal behavior everywhere
# else but eliminates the stall for `npm run offline:local`.
export NODE_OPTIONS="${NODE_OPTIONS:---dns-result-order=ipv4first}"
