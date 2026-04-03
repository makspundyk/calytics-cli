#!/bin/bash
# Service registry — single source of truth for all service metadata

# Ports
declare -A SVC_PORT=(
  [be]=3333
  [a2a]=3000
  [rs]=0          # no HTTP port — stream subscriber
  [admin]=9000
  [fe]=5000
  [docs]=8080
)

# Project directories (relative to CAL_PROJECT)
declare -A SVC_DIR=(
  [be]=calytics-be
  [a2a]=calytics-a2a
  [rs]=calytics-risk-scoring
  [admin]=calytics-be-admin
  [fe]=calytics-fe
  [docs]=client-openapi-docs
)

# Docker container names (only for docker-managed services)
declare -A SVC_CONTAINER=(
  [admin]=calytics_be_admin
  [fe]=calytics_fe
  [docs]=calytics_docs
)

# Start commands (only for process-managed services)
declare -A SVC_START=(
  [be]="npm run offline:local"
  [a2a]="npm run offline:local"
  [rs]="npm run stream:dev"
)

# Log files (only for process-managed services)
declare -A SVC_LOG=(
  [be]=/tmp/calytics-be.log
  [a2a]=/tmp/calytics-a2a.log
  [rs]=/tmp/calytics-risk-scoring.log
)

# Human-readable names
declare -A SVC_LABEL=(
  [be]="calytics-be"
  [a2a]="calytics-a2a"
  [rs]="calytics-risk-scoring"
  [admin]="calytics-be-admin"
  [fe]="calytics-fe"
  [docs]="API docs"
)

# Categorization
SVC_PROCESS_LIST=(be a2a rs)       # started as background Node processes
SVC_DOCKER_LIST=(admin fe docs)    # started as Docker containers
SVC_ALL_LIST=(be a2a rs admin fe docs)

# Resolve alias → canonical name
svc_resolve() {
  case "$1" in
    be|debit-guard|dg|backend) echo "be" ;;
    a2a)                       echo "a2a" ;;
    rs|risk|risk-scoring)      echo "rs" ;;
    admin|be-admin)            echo "admin" ;;
    fe|frontend)               echo "fe" ;;
    docs)                      echo "docs" ;;
    *) return 1 ;;
  esac
}

# Check if a service is docker-managed
svc_is_docker() {
  [[ -n "${SVC_CONTAINER[$1]:-}" ]]
}

# Check if a service is process-managed
svc_is_process() {
  [[ -n "${SVC_START[$1]:-}" ]]
}
