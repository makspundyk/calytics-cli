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

## Repo conventions

- Author for this repo: `Maksym Pundyk <maksym.p@ideainyou.com>`
- Author for all other calytics repos: `Maksym Pundyk <m.pundyk@calytics.io>`
- `cal install` configures this automatically
- Commit messages: imperative mood, short first line, body if needed
