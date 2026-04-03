# Calytics CLI — Development Guidelines

This is a **multi-user CLI SDK** for managing the Calytics local development environment. It is sourced into `~/.bashrc` and runs on different machines, usernames, and directory layouts. Every decision must account for portability.

## Architecture

```
calytics-cli/
├── cal.sh              ← Entry point. Sourced by ~/.bashrc. Defines `cal()` function.
├── lib/
│   ├── colors.sh       ← ANSI colors, info/ok/warn/fail/phase helpers
│   ├── services.sh     ← SERVICE REGISTRY — single source of truth for all metadata
│   └── helpers.sh      ← Shared functions (wait_for_port, kill_port, start/stop helpers)
├── env/
│   └── defaults.sh     ← Default env vars (AWS, Postgres, paths)
├── commands/           ← One file per command (start.sh, stop.sh, restart.sh, etc.)
├── seeders/            ← Data seeding scripts (secrets.sh, api-keys.sh, etc.)
├── infra/              ← Infrastructure (deploy.sh, docker-compose.yml, nuke.sh)
├── test/               ← Test suites and data files
├── vtl/                ← API Gateway VTL tools
└── docs/               ← Reference docs, vendor secrets, investigation notes
```

## Critical Rules

### 1. ZERO hardcoded values in commands

Every command script in `commands/` must use variables from `lib/services.sh`, `lib/helpers.sh`, or `env/defaults.sh`. Never write raw strings for:

| What | Wrong | Right |
|------|-------|-------|
| Ports | `:3333`, `:9000` | `${SVC_PORT[be]}`, `${SVC_PORT[admin]}` |
| Container names | `"calytics_be_admin"` | `"${SVC_CONTAINER[admin]}"` |
| Service directories | `"calytics-be"`, `"calytics-a2a"` | `"${SVC_DIR[be]}"`, `$(svc_path be)` |
| Log files | `"/tmp/calytics-be.log"` | `"${SVC_LOG[be]}"` |
| Docker compose path | `"$CAL_PROJECT/calytics-cli/infra/docker-compose.yml"` | `"$COMPOSE_FILE"` |
| Emails | `"m.pundyk@calytics.io"` | `"$GIT_AUTHOR_EMAIL_COMPANY"` |
| Infra containers | `"localstack_main"` | `"$INFRA_LOCALSTACK_CONTAINER"` |

The ONLY file that may contain raw values is `lib/services.sh` — that's the registry. Everything else reads from it.

### 2. No hardcoded paths or usernames

Paths are always derived from `cal.sh`'s own location:

```bash
CAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # cli directory
CAL_PROJECT="$(cd "$CAL_ROOT/.." && pwd)"                    # project root
```

Never write `/home/username/...` or assume a directory name. If you need the CLI folder name (e.g., for bashrc detection), use:

```bash
CLI_DIRNAME="$(basename "$CAL_ROOT")"
```

### 3. `lib/services.sh` is the single source of truth

When adding a new service:
1. Add it to ALL registries in `services.sh`: `SVC_PORT`, `SVC_DIR`, `SVC_CONTAINER` or `SVC_START`, `SVC_LOG`, `SVC_LABEL`
2. Add it to `SVC_PROCESS_LIST` or `SVC_DOCKER_LIST` and `SVC_ALL_LIST`
3. Add aliases in `svc_resolve()`
4. Every command that iterates services automatically picks it up

### 4. Commands run at top-level, not inside functions

`cal.sh` dispatches commands via `bash -c "source libs; source command.sh"`. This means command scripts execute at the **top level** of a bash process. Therefore:

- **Never use `local`** — it only works inside functions. Use plain variables.
- Variables set in commands are not visible to the parent shell (by design).
- Use `exec` for commands that should replace the process (e.g., `logs.sh` uses `exec tail -f` for clean Ctrl+C handling).

### 5. Every script must be idempotent

Running a command twice must produce the same result. Seeders delete-then-recreate. Build scripts check timestamps. Install skips already-present packages. Never assume clean state.

### 6. Exit codes matter

- `fail()` exits with code 1 — use for unrecoverable errors
- `warn()` prints but continues — use for non-fatal issues
- Commands that resolve a service alias must fail fast on unknown input:
  ```bash
  svc=$(svc_resolve "$target") || fail "Unknown service: $target"
  ```

### 7. infra/deploy.sh is legacy

`infra/deploy.sh` is the migrated `local-deploy.sh` — a large orchestration script that predates the CLI. It uses its own `$SCRIPT_DIR` variable (pointing to project root) and has inline logic that doesn't use the service registry yet. When modifying it, respect its internal conventions. Gradual migration to use `lib/services.sh` is welcome but not required per-change.

## Adding a new command

1. Create `commands/<name>.sh`
2. First lines should be the help comment:
   ```bash
   #!/bin/bash
   # cal <name> [args]
   # One-line description of what this command does.
   ```
3. Source libs are already loaded by `cal.sh` — use `info`, `ok`, `fail`, `phase`, `svc_resolve`, `SVC_*`, `$CAL_ROOT`, `$CAL_PROJECT` directly.
4. Add tab completion in `cal.sh` `_cal_completions()` if the command has subcommands.
5. Add to `commands/help.sh` help text.

## Adding a new service

1. Edit `lib/services.sh` — add to all registries
2. Add alias in `svc_resolve()`
3. Test: `cal start <alias>`, `cal stop <alias>`, `cal restart <alias>`, `cal logs <alias>`, `cal status`
4. No other files should need changes (commands iterate the registry)

## Adding a new seeder

1. Create `seeders/<name>.sh` — must be self-contained (sources env vars from `$CAL_ROOT/env/defaults.sh` if needed, or receives them from the caller)
2. Add to `commands/seed.sh` case statement
3. Add to `commands/help.sh` seed section
4. Add tab completion in `cal.sh`

## Environment variables

Defaults are in `env/defaults.sh`. They use `${VAR:-default}` pattern so environment overrides always win. Docker Compose variables come from `$CAL_PROJECT/.env`.

## Testing changes

After any change:
```bash
source ~/.bashrc          # reload cal
cal help                  # check help renders
cal status                # check service detection
cal restart be            # check a process service
cal restart admin         # check a docker service
cal logs be               # check log tailing (Ctrl+C)
cal build shims           # check build
```

## Keeping the CLI in sync with infrastructure changes

The CLI mirrors infrastructure defined in the service repos. When someone adds a table, queue, secret, service, or env var in a service repo, the CLI must be updated to support it. **This is your highest-priority maintenance task.**

### How to detect drift

Before implementing any feature or fixing any bug in a Calytics service repo, run this audit:

```bash
# 1. Check Terraform for new/changed resources
diff <(grep -r 'resource "aws_' $CAL_PROJECT/terraform/local/*.tf | sort) \
     <(cat $CAL_ROOT/docs/last-known-resources.txt 2>/dev/null | sort)

# 2. Check serverless.yml for new CloudFormation resources
grep -A1 'Type: AWS::' $CAL_PROJECT/calytics-be/serverless.yml

# 3. Check .env files for new variables
for svc in be a2a admin rs; do
  echo "=== ${svc} ==="
  diff <(grep -oP '^[A-Z_]+=' "$CAL_PROJECT/${SVC_DIR[$svc]}/.env" 2>/dev/null | sort) \
       <(grep -oP '^[A-Z_]+=' "$CAL_PROJECT/${SVC_DIR[$svc]}/.env.example" 2>/dev/null | sort)
done

# 4. Check for new services/repos
ls -d $CAL_PROJECT/calytics-*/ | xargs -I{} basename {}
```

### Change-to-file mapping

When you detect a change in a service repo, update the CLI following this mapping:

| What changed | Where it's defined | CLI files to update |
|---|---|---|
| **New DynamoDB table** | `terraform/local/calytics-be.tf` or `serverless.yml` Resources section or `seeders/a2a-tables.sh` | `seeders/a2a-tables.sh` (if A2A/CC table), `commands/system-check.sh` (add consistency check), `infra/deploy.sh` (if terraform-managed) |
| **New SQS queue** | `terraform/local/calytics-be.tf` or `seeders/queues.sh` | `seeders/queues.sh` (add queue creation + DLQ + redrive policy) |
| **New Secrets Manager secret** | `terraform/local/calytics-be.tf` or `seeders/secrets.sh` | `seeders/secrets.sh` (add create-secret block) |
| **New S3 bucket** | `terraform/local/calytics-be.tf` or `terraform/local/calytics-a2a.tf` | Terraform handles it — no seeder change needed |
| **New service/repo** | New directory in `$CAL_PROJECT/` | `lib/services.sh` (all registries), `svc_resolve()`, `commands/help.sh`, `cal.sh` (tab completion), `infra/docker-compose.yml` (if Docker-managed) |
| **New env var in a service .env** | `calytics-*/env` or `.env.example` | `commands/system-check.sh` (add to consistency checks if shared across repos), `env/defaults.sh` (if it needs a default) |
| **New seeder/seed script** | Inline in deploy.sh or standalone | `seeders/<name>.sh` (new file), `commands/seed.sh` (add case), `commands/help.sh`, `cal.sh` (tab completion) |
| **Port change** | `serverless.yml` custom.serverless-offline, `docker-compose.yml` | `lib/services.sh` (SVC_PORT) — propagates everywhere automatically |
| **New npm script** (e.g., new migration) | Service `package.json` | `commands/migrate.sh` or `commands/build.sh` (add case if needed) |
| **New Terraform resource type** | `terraform/local/*.tf` | `infra/deploy.sh` (Terraform phase), possibly `commands/system-check.sh` |
| **Docker Compose service added** | `infra/docker-compose.yml` | `lib/services.sh` (add to SVC_CONTAINER, SVC_DOCKER_LIST), `infra/docker-compose.yml` |
| **Shared module added** | New dir in `calytics-shared-modules/` | `commands/build.sh` shared section handles it automatically (iterates all git repos). `commands/system-check.sh` also auto-discovers. No change needed unless it needs special handling. |
| **API key product added** | `seeders/api-keys.sh` hardcoded list | `seeders/api-keys.sh` (add product + key), `commands/system-check.sh` (if consistency check needed) |
| **Webhook event type added** | `seeders/webhooks.sh` | `seeders/webhooks.sh` (add to webhook event list) |
| **Product plan added** | `seeders/plans.sh` | Usually auto-discovered from `product_plans_product_type_enum` — no change. Only update if plan defaults (price, limits) differ. |

### Step-by-step: when asked to work on a Calytics service repo

1. **Before starting work**, scan for CLI drift:
   - Read the service's `.env`, `serverless.yml`, `terraform/*.tf`, and `package.json`
   - Compare DynamoDB table names, SQS queue names, secret IDs against CLI seeders
   - Check if `lib/services.sh` has the correct port, directory, and container name

2. **During implementation**, if you add or change:
   - A DynamoDB table → update the relevant seeder AND `system-check.sh`
   - An SQS queue → update `seeders/queues.sh`
   - A secret → update `seeders/secrets.sh`
   - An environment variable shared across repos → update `commands/system-check.sh` consistency section
   - A service port → update `lib/services.sh`

3. **After implementation**, verify:
   ```bash
   cal system-check    # all checks should pass
   cal seed all        # seeders should complete without errors
   cal status          # all services detected correctly
   ```

### Proactive detection patterns

When reading code in any Calytics service, watch for these patterns that indicate CLI updates are needed:

```typescript
// New DynamoDB table → needs seeder or terraform resource
new DynamoDBClient(...).send(new CreateTableCommand({ TableName: "calytics-..." }))
@Entity({ tableName: process.env.NEW_TABLE_NAME })

// New SQS queue → needs seeder
process.env.NEW_QUEUE_URL
new SQSClient(...).send(new SendMessageCommand({ QueueUrl: "..." }))

// New secret → needs seeder
secretsManager.getSecretValue({ SecretId: "calytics/new/secret/path" })
process.env.NEW_SECRET_ID

// New service port → needs services.sh update
httpServer.listen(NEW_PORT)
custom.serverless-offline.httpPort: NEW_PORT
```

### The `cal sync terraform` connection

`cal sync terraform` runs `sync-local-terraform.sh` which auto-generates LocalStack-compatible Terraform from the real environment configs. When Terraform configs change in the service repos:

1. Run `cal sync terraform` to pull changes
2. Review the diff in `terraform/local/*.tf`
3. If new resources were added (tables, queues, secrets), update the corresponding seeders
4. If resources were renamed or removed, update seeders AND `system-check.sh`

### What should NEVER be in the CLI

- Application business logic
- Service-specific TypeScript/JavaScript code
- Test fixtures that belong in the service repo
- Credentials or tokens (use env vars / Secrets Manager)

The CLI is **infrastructure and orchestration only**.

## Repo conventions

- Author for this repo: `Maksym Pundyk <maksym.p@ideainyou.com>`
- Author for all other calytics repos: `Maksym Pundyk <m.pundyk@calytics.io>`
- `cal install` configures this automatically
- Commit messages: imperative mood, short first line, body if needed
