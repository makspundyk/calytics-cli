#!/bin/bash
# cal destroy
# Tear down the entire local environment (containers, volumes, processes, terraform state).

phase "Destroying local environment"

info "Stopping Docker containers..."
dc --profile app --profile docs down -v 2>/dev/null || true

if [ -d "$TF_DIR/.terraform" ]; then
  info "Destroying Terraform resources..."
  (cd "$TF_DIR" && terraform destroy -var-file="env/development.tfvars" -auto-approve 2>/dev/null) || true
fi

info "Killing service processes..."
for svc in "${SVC_ALL_LIST[@]}"; do
  port="${SVC_PORT[$svc]}"
  [ "$port" -gt 0 ] && kill_port "$port"
done
kill_port "$INFRA_LOCALSTACK_PORT"
pgrep -f "${SVC_DIR[rs]}" 2>/dev/null | xargs kill -9 2>/dev/null || true

ok "Environment destroyed"
