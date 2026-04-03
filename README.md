# Calytics CLI (`cal`)

One command to manage the entire local development environment.

## Setup

Already configured in `~/.bashrc`. Open a new terminal or run:
```bash
source ~/.bashrc
```

## Commands

### Services

```bash
cal start [service|all]       # Start one or all services
cal stop [service|all]        # Stop one or all services
cal restart <service>         # Restart a single service
cal status                    # Show what's running
cal logs <service>            # Tail logs (Ctrl+C to stop)
```

### Infrastructure

```bash
cal deploy                    # Full local environment (infra + terraform + seeds + services)
cal deploy --services-only    # Skip infra, just start services
cal deploy --infra-only       # Just LocalStack + Postgres
cal deploy debit-guard        # Only BE + admin
cal deploy a2a                # Only A2A + admin
cal destroy                   # Tear down everything
```

### Build

```bash
cal build shared              # Sync & build shared modules (git fetch + smart build)
cal build shims               # Build alias shims + patch pino for calytics-be
cal build be                  # Build calytics-be
cal build admin               # Build calytics-be-admin
cal build a2a                 # Build calytics-a2a
```

### Seed

```bash
cal seed all                  # Run all seeders
cal seed secrets              # Seed LocalStack Secrets Manager
cal seed queues               # Seed SQS queues
cal seed client               # Seed main client
cal seed admins               # Seed admin users
cal seed webhooks             # Seed webhooks + API settings
cal seed plans                # Seed product plans + subscriptions
cal seed api-keys             # Seed API keys
cal seed ses                  # Verify SES email identity
cal seed a2a-tables           # Create A2A DynamoDB tables
```

### Migrate

```bash
cal migrate run               # Run next pending PostgreSQL migration
cal migrate run --all         # Run all pending migrations
cal migrate revert            # Revert last migration
cal migrate revert --all      # Revert all migrations
cal migrate dynamo            # Run DynamoDB migrations
```

### Sync

```bash
cal sync finapi               # Sync FinAPI sandbox credentials to local
cal sync qonto                # Sync Qonto production credentials to local
cal sync terraform            # Sync Terraform configs from dev environment
```

### Tools

```bash
cal dynamo-gui                # Start DynamoDB admin web UI (:8001)
```

## Service Aliases

| Alias | Service | Port |
|-------|---------|------|
| `be` | calytics-be | 3333 |
| `a2a` | calytics-a2a | 3000 |
| `rs` | calytics-risk-scoring | stream |
| `admin` | calytics-be-admin | 9000 |
| `fe` | calytics-fe | 5000 |
| `docs` | API docs | 8080 |

## Credentials

| Role | Email | Password |
|------|-------|----------|
| Client | main.client@gmail.com | ClientSecret123! |
| Admin | app.admin@gmail.com | AdminSecret123! |

## Tab Completion

Works out of the box. Type `cal ` then Tab to see available commands.
Type `cal restart ` then Tab to see service names.

## Directory Structure

```
cli/
├── cal.sh              Entry point (sourced by ~/.bashrc)
├── commands/           Command implementations
├── seeders/            Data seeding scripts
├── infra/              Infrastructure management
├── lib/                Shared utilities
├── env/                Environment config
├── test/               Test suites
├── vtl/                API Gateway VTL tools
└── docs/               Credential docs & utilities
```
