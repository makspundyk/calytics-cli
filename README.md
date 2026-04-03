# Calytics CLI (`cal`)

One command to manage the entire local development environment.

## First-time install (fresh Linux)

```bash
bash ~/projects/calytics/calytics-cli/commands/install.sh
```

This installs everything (git, docker, node 22, aws cli, terraform, serverless, ngrok, claude-code), fixes permissions, sets git authors, and registers `cal` in your shell. After it finishes, `cal` is ready — no restart needed.

## Already installed

```bash
source ~/.bashrc       # or open a new terminal
cal help
```

Re-run install anytime to pick up missing tools:
```bash
cal install
```

## Commands

### Services

```bash
cal start                     # Start all (infra + services)
cal start infra               # Start just LocalStack + Postgres
cal start <service>           # Start one (auto-starts infra if needed)
cal stop                      # Stop all app services (keeps infra)
cal stop infra                # Stop everything (services + infra)
cal stop <service>            # Stop one service
cal restart <service>         # Restart a single service
cal status                    # Show what's running
cal logs <service>            # Tail logs (Ctrl+C to stop)
cal open <service>            # Open service URL in browser
```

> **Infra dependency:** `be`, `a2a`, `rs`, `admin`, `fe` need LocalStack + Postgres.
> Starting any of them auto-starts infra if it's down.
> `docs` and `dynamo-gui` are independent.

### Deploy (full environment orchestration)

Sets up **everything** needed for a working local environment: infrastructure (LocalStack, Postgres), Terraform resources, database migrations, seed data, and starts services.

```bash
cal deploy                    # Full setup from scratch
cal deploy debit-guard        # Only BE + admin (skips a2a, risk, fe, docs)
cal deploy dg                 # Same (shorthand)
cal deploy a2a                # Only A2A + admin
cal deploy backend            # All backends (skips fe, docs)
cal deploy fe                 # Admin + frontend
cal deploy full               # Everything
cal deploy --services-only    # Skip infra (LocalStack/Postgres already running)
cal deploy --infra-only       # Only start LocalStack + Postgres
cal deploy --skip=a2a,rs      # Skip specific services
cal deploy --env=sandbox      # Use sandbox naming for resources
cal destroy                   # Tear down everything
```

### Build (compile code only)

Compiles code **without** touching infrastructure, seeds, or services. Use after pulling changes or editing shared modules.

```bash
cal build shared              # Git fetch + smart branch switch + build shared modules
cal build shims               # Build alias shims + patch pino (calytics-be local dev)
cal build be                  # Compile calytics-be (tsup)
cal build admin               # Compile calytics-be-admin (NestJS)
cal build a2a                 # Compile calytics-a2a (tsc)
cal build docs                # Pull latest redocly image + rebuild API docs
```

> **When to use which?**
> - First time / fresh machine → `cal deploy`
> - Infrastructure already running, just pulled code → `cal build shared && cal build shims`
> - Changed a shared module → `cal build shared`
> - Changed `src/infrastructure/` in calytics-be → `cal build shims`
> - Want to restart everything from scratch → `cal destroy && cal deploy`

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

### Git (across all repos)

```bash
cal git fetch                 # Fetch all remotes + show behind/ahead/dirty
cal git status                # Show branch + dirty state (no network)
```

### Sync

```bash
cal sync finapi               # Sync FinAPI sandbox credentials to local
cal sync qonto                # Sync Qonto production credentials to local
cal sync terraform            # Sync Terraform configs from dev environment
```

### Daily

```bash
cal morning                   # Fetch repos + system check + start everything
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
