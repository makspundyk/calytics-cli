#!/bin/bash
# Service registry — functions and helpers.
# All names, ports, paths, and config live in lib/names.sh.
# This file provides functions that operate on that data.

# ── Source the names registry ────────────────────────────────────
source "$(dirname "${BASH_SOURCE[0]}")/names.sh"

# ── Alias resolution ────────────────────────────────────────────
svc_resolve() {
  case "$1" in
    be|debit-guard|dg|backend) echo "be" ;;
    a2a)                       echo "a2a" ;;
    cp|cross-product|xp|pr|payment-reconciliation|dr|dispute-recognition)
                               echo "cp" ;;
    rs|risk|risk-scoring)      echo "rs" ;;
    rs-api|rsapi|rs:api|risk-scoring-api)
                               echo "rs-api" ;;
    admin|be-admin)            echo "admin" ;;
    fe|frontend)               echo "fe" ;;
    docs)                      echo "docs" ;;
    dynamo-gui|dynamo|dg-ui)   echo "dynamo-gui" ;;
    webhooks|webhook|wh)       echo "webhooks" ;;
    *) return 1 ;;
  esac
}

# ── Type checks ──────────────────────────────────────────────────
svc_is_docker()  { [[ -n "${SVC_CONTAINER[$1]:-}" ]]; }
svc_is_process() { [[ -n "${SVC_START[$1]:-}" ]]; }

# ── Path getters ─────────────────────────────────────────────────
svc_path()    { echo "$CAL_PROJECT/${SVC_DIR[$1]}"; }
cmd_path()    { echo "$CAL_ROOT/commands/${1}.sh"; }
seeder_path() { echo "$CAL_ROOT/seeders/${1}.sh"; }

# ── Cross-script runners ────────────────────────────────────────
run_cmd()    { source "$(cmd_path "$1")" "${@:2}"; }
run_seeder() { bash "$(seeder_path "$1")"; }

# ── Infra dependency check ───────────────────────────────────────
svc_needs_infra() {
  for dep in "${SVC_INFRA_DEPENDENT[@]}"; do
    [ "$dep" = "$1" ] && return 0
  done
  return 1
}

# ── Serverless framework check ───────────────────────────────────
# True if the service's start command uses Serverless Framework v4,
# which makes the process vulnerable to api.serverless.com timeouts.
svc_uses_serverless() {
  for s in "${SVC_USES_SERVERLESS[@]}"; do
    [ "$s" = "$1" ] && return 0
  done
  return 1
}
