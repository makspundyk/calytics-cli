#!/bin/bash
# cal seed <target>
# Run seeders to populate the local environment with test data.
#
# Targets:
#   all         Run all seeders in order
#   secrets     Seed LocalStack Secrets Manager
#   queues      Seed SQS queues
#   ses         Verify SES email identity
#   client      Seed main client
#   admins      Seed admin users
#   webhooks    Seed webhooks + API settings
#   plans       Seed product plans + subscriptions
#   api-keys    Seed API keys (DB + API Gateway + encryption)
#   a2a-tables  Create A2A + CC DynamoDB tables

target="${1:-}"
[ -z "$target" ] && fail "Usage: cal seed <target> (all, secrets, queues, client, admins, webhooks, plans, api-keys, ses, a2a-tables)"

_seed() {
  script="$(seeder_path "$1")"
  if [ -f "$script" ]; then
    info "Seeding: $1"
    run_seeder "$1"
    ok "$1 seeded"
  else
    warn "Seeder not found: $1"
  fi
}

case "$target" in
  all)
    phase "Running all seeders"
    _seed secrets
    _seed queues
    _seed ses
    # client + admins via be-admin npm scripts
    info "Seeding admins..."
    (cd "$BE_ADMIN_DIR" && npm run seed:admins 2>&1 | tail -3)
    ok "Admins seeded"
    _seed client
    _seed webhooks
    _seed plans
    _seed api-keys
    ok "All seeders complete"
    ;;
  admins)
    phase "Seeding admins"
    (cd "$BE_ADMIN_DIR" && npm run seed:admins 2>&1 | tail -3)
    ok "Admins seeded"
    ;;
  *)
    phase "Seeding: $target"
    _seed "$target"
    ;;
esac
