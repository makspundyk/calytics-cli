#!/bin/bash
# cal help [command]

cmd="${1:-}"

if [ -n "$cmd" ] && [ -f "$CAL_ROOT/commands/${cmd}.sh" ]; then
  # Show help for specific command
  head -20 "$CAL_ROOT/commands/${cmd}.sh" | grep '^#' | grep -v '^#!/' | sed 's/^# \?//'
  exit 0
fi

cat << 'EOF'

  ╔═══════════════════════════════════════════╗
  ║           Calytics CLI  (cal)             ║
  ╚═══════════════════════════════════════════╝

  SERVICES
    cal start [service|all]       Start one or all services
    cal stop [service|all]        Stop one or all services
    cal restart <service>         Restart a single service
    cal status                    Show what's running
    cal logs <service>            Tail logs for a service

  INFRASTRUCTURE
    cal deploy [flags]            Full local environment setup
    cal destroy                   Tear down everything

  BUILD
    cal build shared              Sync & build shared modules
    cal build shims               Build alias shims + patch pino
    cal build <service>           Build a specific service

  SEED
    cal seed all                  Run all seeders
    cal seed secrets              Seed LocalStack Secrets Manager
    cal seed queues               Seed SQS queues
    cal seed client               Seed main client
    cal seed admins               Seed admin users
    cal seed webhooks             Seed webhooks + API settings
    cal seed plans                Seed product plans + subscriptions
    cal seed api-keys             Seed API keys
    cal seed ses                  Verify SES email identity
    cal seed a2a-tables           Create A2A DynamoDB tables

  MIGRATE
    cal migrate run [--all]       Run PostgreSQL migrations
    cal migrate revert [--all]    Revert PostgreSQL migrations
    cal migrate dynamo            Run DynamoDB migrations

  SYNC
    cal sync finapi               Sync FinAPI credentials to local
    cal sync qonto                Sync Qonto credentials to local
    cal sync terraform            Sync Terraform from dev env

  TOOLS
    cal dynamo-gui                Start DynamoDB admin web UI
    cal vtl <subcommand>          API Gateway VTL management

  SETUP
    cal install                   Install all system dependencies + register CLI
    cal system-check              Full diagnostic report (tools, env, consistency)

  SERVICES
    be        calytics-be             :3333
    a2a       calytics-a2a            :3000
    rs        calytics-risk-scoring   (stream)
    admin     calytics-be-admin       :9000
    fe        calytics-fe             :5000
    docs      API docs                :8080

EOF
