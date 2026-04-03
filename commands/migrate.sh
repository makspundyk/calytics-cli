#!/bin/bash
# cal migrate <action> [--all]
# Run or revert PostgreSQL migrations, or run DynamoDB migrations.
#
# Actions:
#   run [--all]      Run next (or all) pending PostgreSQL migrations
#   revert [--all]   Revert last (or all) PostgreSQL migrations
#   dynamo           Run DynamoDB migrations

action="${1:-}"
flag="${2:-}"
[ -z "$action" ] && fail "Usage: cal migrate <run|revert|dynamo> [--all]"

cd "$BE_ADMIN_DIR" || fail "calytics-be-admin not found at $BE_ADMIN_DIR"

case "$action" in
  run)
    if [ "$flag" = "--all" ]; then
      phase "Running all PostgreSQL migrations"
      npm run --silent postgres:migration:run:all 2>&1
    else
      phase "Running next PostgreSQL migration"
      npm run --silent postgres:migration:run 2>&1
    fi
    ok "Migrations complete"
    ;;
  revert)
    if [ "$flag" = "--all" ]; then
      phase "Reverting all PostgreSQL migrations"
      npm run --silent postgres:migration:revert:all 2>&1
    else
      phase "Reverting last PostgreSQL migration"
      npm run --silent postgres:migration:revert 2>&1
    fi
    ok "Revert complete"
    ;;
  dynamo)
    phase "Running DynamoDB migrations"
    npm run --silent dynamo:migrate 2>&1
    ok "DynamoDB migrations complete"
    ;;
  *)
    fail "Unknown action: $action (try: run, revert, dynamo)"
    ;;
esac
