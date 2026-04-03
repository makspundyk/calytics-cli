#!/bin/bash
# cal deploy [flags]
# Full local environment setup: infrastructure, terraform, database, seeds, services.
#
# Flags:
#   --services-only    Skip infrastructure, just start services
#   --infra-only       Just infrastructure (LocalStack + Postgres)
#   --skip=<list>      Skip specific services (comma-separated: be,a2a,rs,fe,docs)
#   --env=<name>       Environment name (default: development)

# Re-exec the full local-deploy.sh with all args — it has the complete orchestration logic
exec bash "$CAL_ROOT/infra/deploy.sh" "$@"
