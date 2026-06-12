# Calytics CLI (`cal`)

One command to manage the entire local development environment.

> **Design principle:** Everything must be fully autonomous. A teammate with a fresh laptop runs ONE command and gets a working environment. No extra manual steps, no "also run this", no "don't forget to install X". If `cal install` doesn't cover it, it's a bug.

## First-time install (fresh laptop)

```bash
bash ~/projects/calytics/calytics-cli/commands/install.sh
```

This single command:
- Registers `cal` in your shell (available immediately, no restart)
- Creates `.env` and `.env.local` if missing (auto-detects WSL IP)
- Installs: git, curl, jq, docker, node 22, aws cli, terraform, serverless, ngrok, claude-code
- Pre-pulls Docker images (LocalStack, Postgres, webhook-tester, DynamoDB GUI, Redocly)
- Fixes file permissions across all repos
- Configures git author for every repo

After install:
```bash
cal morning    # fetch repos + system check + start everything
```

## Already installed

```bash
cal install    # re-run anytime — skips what's already present
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

> **Infra dependency:** `be`, `a2a`, `cp`, `rs`, `admin`, `fe` need LocalStack + Postgres.
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
cal seed a2a-payments         # Lifecycle-coverage A2A payment fixture rows
cal seed cross-product-tables # Create cross-product DDB tables (worker-tasks, returns-log)
```

### Migrate

```bash
cal migrate run               # Run next pending PostgreSQL migration
cal migrate run --all         # Run all pending migrations
cal migrate revert            # Revert last migration
cal migrate revert --all      # Revert all migrations
cal migrate dynamo            # Run DynamoDB migrations
```

### Risk Scoring

Subscribe to a remote DynamoDB Stream and run the risk-scoring pipeline locally. Reads real events from development/sandbox, scores them through the engine, writes results to LocalStack.

```bash
cal rs stream dev                    # DG verifications, live (new records only)
cal rs stream dev --history          # DG verifications, from oldest available
cal rs stream sandbox                # DG verifications on sandbox
cal rs stream dev --source a2a       # A2A payments stream
cal rs stream dev --source all       # Both DG + A2A (parallel)
```

> **Prerequisites:** AWS credentials (`aws sso login`), LocalStack running (`cal start infra`), RS tables migrated (`cal migrate dynamo`).
>
> **Why no `local`?** LocalStack doesn't support DDB Streams cross-service. The subscriber always reads from real AWS and writes to local LocalStack.

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
| `cp` (also `xp`, `pr`, `dr`) | calytics-cross-product (Payment Reconciliation + Dispute Recognition) | 3046 (lambda invoke; no HTTP API) |
| `rs` | calytics-risk-scoring stream subscriber (manual: `cal rs stream <env>`) | — |
| `rs-api` (also `rsapi`) | risk-scoring query Lambdas (getScore/batch/history/reputation) — what the SDK calls | 4002 |
| `admin` | calytics-be-admin | 9000 |
| `fe` | calytics-fe | 5000 |
| `docs` | API docs | 8080 |
| `dynamo-gui` | DynamoDB admin | 8001 |
| `webhooks` | Webhook tester (UI + file persistence) | 8090 |
| `finapi-mock` | Stateful finAPI mock for lifecycle/cleanup QA (`tools/finapi-mock-server.js`; aliases `mock`, `finapi`) | 4010 |

### Webhook Tester

Local alternative to webhook.site, backed by `ghcr.io/tarampampam/webhook-tester:2`. Captured payloads live in the `webhook_data` Docker volume and the in-container `/data` directory; query them via the tester's API or the web UI.

Each product has a stable webhook endpoint pinned in `lib/names.sh` (run with `--auto-create-sessions`, so the UUIDs auto-materialize the first time they're hit):
- **DebitGuard:** `http://localhost:8090/a0937803-8760-4282-83ce-873ca2d1d78c`
- **OwnershipCheck:** `http://localhost:8090/844af3bb-3fda-45df-a823-d4ef235309dc`
- **A2A + CC:** `http://localhost:8090/f5e27a02-ad19-4641-8e56-8bc9f4d33cfb`

`cal seed webhooks` writes these URLs into the admin DB (`client_webhooks`) and ensures each session exists. Use `cal open webhooks [dg|oc|a2a]` to jump into the inspector UI.

For remote testing (e.g. development env → local): use ngrok to expose the webhook port:
```bash
ngrok http 8090
# Then set the ngrok URL in the admin UI for the development environment
```

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
├── cal.sh              Entry point (sourced by ~/.bashrc or ~/.zshrc — bash & zsh, Linux & macOS)
├── commands/           Command implementations
├── seeders/            Data seeding scripts
├── infra/              Infrastructure management
├── lib/                Shared utilities
├── env/                Environment config
├── test/               Test suites
├── vtl/                API Gateway VTL tools
└── docs/               Credential docs & utilities
```
