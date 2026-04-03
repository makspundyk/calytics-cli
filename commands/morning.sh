#!/bin/bash
# cal morning
# Full morning routine: fetch all repos, check system health, start everything.

phase "Good morning"

# 1. Fetch all repos
info "Fetching all repos..."
bash "$CAL_ROOT/commands/git.sh" fetch

# 2. System check (abbreviated — skip long checks, just show issues)
info "Running system check..."
bash "$CAL_ROOT/commands/system-check.sh"

# 3. Start everything
info "Starting environment..."
bash "$CAL_ROOT/commands/start.sh" all
