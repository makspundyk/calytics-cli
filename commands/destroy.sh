#!/bin/bash
# cal destroy
# Tear down the entire local environment (containers, volumes, processes, terraform state).

phase "Destroying local environment"

info "Stopping Docker containers..."
docker compose -f "$CAL_ROOT/infra/docker-compose.yml" --env-file "$CAL_PROJECT/.env" --profile app --profile docs down -v 2>/dev/null || true

TF_DIR="$CAL_PROJECT/terraform/local"
if [ -d "$TF_DIR/.terraform" ]; then
  info "Destroying Terraform resources..."
  (cd "$TF_DIR" && terraform destroy -var-file="env/development.tfvars" -auto-approve 2>/dev/null) || true
fi

info "Killing service processes..."
for port in 9000 5000 3333 3000 4566; do
  kill_port "$port"
done
pgrep -f "calytics-risk-scoring" 2>/dev/null | xargs kill -9 2>/dev/null || true

ok "Environment destroyed"
