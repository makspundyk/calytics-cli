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

run_seeder() {
  local name="$1" script="$CAL_ROOT/seeders/${name}.sh"
  if [ -f "$script" ]; then
    info "Seeding: $name"
    bash "$script"
    ok "$name seeded"
  else
    warn "Seeder not found: $script"
  fi
}

case "$target" in
  all)
    phase "Running all seeders"
    run_seeder secrets
    run_seeder queues
    run_seeder ses
    # client + admins via be-admin npm scripts
    info "Seeding admins..."
    (cd "$BE_ADMIN_DIR" && npm run seed:admins 2>&1 | tail -3)
    ok "Admins seeded"
    run_seeder client
    run_seeder webhooks
    run_seeder plans
    run_seeder api-keys
    ok "All seeders complete"
    ;;
  admins)
    phase "Seeding admins"
    (cd "$BE_ADMIN_DIR" && npm run seed:admins 2>&1 | tail -3)
    ok "Admins seeded"
    ;;
  *)
    phase "Seeding: $target"
    run_seeder "$target"
    ;;
esac
