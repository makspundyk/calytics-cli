#!/bin/bash
# cal sync <target>
# Sync credentials or config from AWS to LocalStack.
#
# Targets:
#   finapi      Sync FinAPI sandbox credentials
#   qonto       Sync Qonto production credentials
#   terraform   Sync Terraform configs from dev environment

target="${1:-}"
[ -z "$target" ] && fail "Usage: cal sync <target> (finapi, qonto, terraform)"

case "$target" in
  finapi)
    phase "Syncing FinAPI sandbox credentials to LocalStack"
    bash "$CAL_ROOT/infra/sync-secrets.sh" finapi
    ;;
  qonto)
    phase "Syncing Qonto production credentials to LocalStack"
    bash "$CAL_ROOT/infra/sync-secrets.sh" qonto
    ;;
  terraform)
    phase "Syncing Terraform from dev environment"
    local tf_script="$CAL_PROJECT/scripts/sync-local-terraform.sh"
    [ -f "$tf_script" ] && bash "$tf_script" || fail "sync-local-terraform.sh not found"
    ;;
  *)
    fail "Unknown sync target: $target (try: finapi, qonto, terraform)"
    ;;
esac
