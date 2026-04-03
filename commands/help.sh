#!/bin/bash
# cal help [command]

cmd="${1:-}"

if [ -n "$cmd" ] && [ -f "$CAL_ROOT/commands/${cmd}.sh" ]; then
  head -20 "$CAL_ROOT/commands/${cmd}.sh" | grep '^#' | grep -v '^#!/' | sed 's/^# \?//'
  exit 0
fi

cat << 'EOF'

  ╔═══════════════════════════════════════════╗
  ║           Calytics CLI  (cal)             ║
  ╚═══════════════════════════════════════════╝

  SERVICES
    cal start                     Start all (infra + services)
    cal start infra               Start just LocalStack + Postgres
    cal start <service>           Start one service (auto-starts infra if needed)
    cal stop                      Stop all app services (keeps infra)
    cal stop infra                Stop everything (services + infra)
    cal stop <service>            Stop one service
    cal restart <service>         Restart a single service
    cal status                    Show what's running
    cal logs <service>            Tail logs (last 80 lines + follow)
    cal open <service>            Open service URL in browser

  DEPLOY (full environment orchestration)
    cal deploy                    Full setup: infra → terraform → db → seeds → services
    cal deploy debit-guard        Only BE + admin (skips a2a, risk, fe, docs)
    cal deploy dg                 Same as above (shorthand)
    cal deploy a2a                Only A2A + admin
    cal deploy backend            All backends (skips fe, docs)
    cal deploy fe                 Admin + frontend
    cal deploy full               Everything
    cal deploy --services-only    Skip infra (LocalStack/Postgres already running)
    cal deploy --infra-only       Only start LocalStack + Postgres
    cal deploy --skip=a2a,rs      Skip specific services
    cal deploy --env=sandbox      Use sandbox naming for resources
    cal deploy --destroy          Tear down everything
    cal destroy                   Same as above

  BUILD (compile code, no infrastructure)
    cal build shared              Git fetch + smart branch switch + build shared modules
    cal build shims               Build alias shims + patch pino (calytics-be)
    cal build be                  Compile calytics-be (tsup)
    cal build admin               Compile calytics-be-admin (NestJS)
    cal build a2a                 Compile calytics-a2a (tsc)
    cal build docs                Pull latest redocly image + rebuild docs

  SEED
    cal seed all                  Run all seeders in order
    cal seed secrets              LocalStack Secrets Manager (vendor creds, encryption keys)
    cal seed queues               SQS queues + DLQs + redrive policies
    cal seed client               Main client (main.client@gmail.com)
    cal seed admins               Admin users (app.admin@gmail.com)
    cal seed webhooks             Webhooks + API settings for main client
    cal seed plans                Product plans + subscriptions
    cal seed api-keys             API keys (DB + API Gateway + encryption)
    cal seed ses                  Verify SES email identity
    cal seed a2a-tables           A2A + Calytics Collect DynamoDB tables

  MIGRATE
    cal migrate run               Run next pending PostgreSQL migration
    cal migrate run --all         Run all pending migrations
    cal migrate revert            Revert last migration
    cal migrate revert --all      Revert all migrations
    cal migrate dynamo            Run DynamoDB migrations

  GIT
    cal git fetch                 Fetch all repos + show branch/behind/dirty status
    cal git status                Show branch + dirty state (no fetch)

  SYNC
    cal sync finapi               Sync FinAPI sandbox credentials → LocalStack
    cal sync qonto                Sync Qonto prod credentials → LocalStack
    cal sync terraform            Sync Terraform configs from dev environment

  DAILY
    cal morning                   Fetch repos + system check + start everything

  SETUP
    cal install                   Install all system deps + register CLI
    cal system-check              Full diagnostic (tools, env, consistency)

  SERVICE ALIASES
    be, dg      calytics-be             :3333
    a2a         calytics-a2a            :3000
    rs          calytics-risk-scoring   (stream)
    admin       calytics-be-admin       :9000
    fe          calytics-fe             :5000
    docs        API docs                :8080
    dynamo-gui  DynamoDB admin web UI   :8001

  DEPLOY vs BUILD
    deploy = infrastructure + terraform + database + seeds + start services
             (runs everything needed for a working local environment)
    build  = compile code only, no infrastructure, no seeds, no services
             (use after pulling code changes or editing shared modules)

EOF
