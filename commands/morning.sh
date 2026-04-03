#!/bin/bash
# cal morning
# Full morning routine: fetch all repos, check system health, start everything.

phase "Good morning"

# 1. Fetch all repos
info "Fetching all repos..."
run_cmd git fetch

# 2. System check
info "Running system check..."
run_cmd system-check

# 3. Start everything
info "Starting environment..."
run_cmd start all
