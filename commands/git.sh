#!/bin/bash
# cal git <subcommand>
# Git operations across all repos.
#
# Subcommands:
#   cal git fetch         Fetch all remotes + show branch status
#   cal git status        Show branch + dirty state for all repos

subcmd="${1:-}"
[ -z "$subcmd" ] && fail "Usage: cal git <fetch|status>"

# Collect all repo directories (root-level + shared modules)
REPOS=()
for dir in "$CAL_PROJECT"/*/; do
  [ -d "$dir/.git" ] && REPOS+=("$dir")
done
if [ -d "$CAL_PROJECT/calytics-shared-modules" ]; then
  for dir in "$CAL_PROJECT/calytics-shared-modules"/*/; do
    [ -d "$dir/.git" ] && REPOS+=("$dir")
  done
fi

# Detect the default branch for a repo (main, master, or development)
detect_default_branch() {
  cd "$1" || return
  for branch in main master development; do
    if git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
      echo "$branch"
      return
    fi
  done
  echo "main"  # fallback
}

case "$subcmd" in
  fetch)
    phase "Fetching all repos"

    for repo_dir in "${REPOS[@]}"; do
      name=$(basename "$repo_dir")
      # Indent shared module names
      [[ "$repo_dir" == *"calytics-shared-modules"* ]] && name="shared/$name"

      current=$(cd "$repo_dir" && git branch --show-current 2>/dev/null)
      default_branch=$(detect_default_branch "$repo_dir")

      # Fetch
      (cd "$repo_dir" && git fetch origin --quiet 2>/dev/null)

      # Calculate ahead/behind vs default branch
      behind=$(cd "$repo_dir" && git rev-list --count "HEAD..origin/$default_branch" 2>/dev/null || echo "?")
      ahead=$(cd "$repo_dir" && git rev-list --count "origin/$default_branch..HEAD" 2>/dev/null || echo "?")

      # Dirty state
      dirty=$(cd "$repo_dir" && git status --porcelain 2>/dev/null | wc -l)

      # Format status line
      label=$(printf "%-35s" "$name")
      branch_info="${CYAN}${current}${NC}"

      status_parts=""
      if [ "$current" = "$default_branch" ]; then
        if [ "$behind" -gt 0 ] 2>/dev/null; then
          status_parts="${YELLOW}${behind} behind${NC}"
        else
          status_parts="${GREEN}up to date${NC}"
        fi
      else
        if [ "$ahead" -gt 0 ] 2>/dev/null; then
          status_parts="${MAGENTA}${ahead} ahead${NC}"
        fi
        if [ "$behind" -gt 0 ] 2>/dev/null; then
          [ -n "$status_parts" ] && status_parts="$status_parts, "
          status_parts="${status_parts}${YELLOW}${behind} behind ${default_branch}${NC}"
        fi
      fi

      if [ "$dirty" -gt 0 ] 2>/dev/null; then
        [ -n "$status_parts" ] && status_parts="$status_parts, "
        status_parts="${status_parts}${RED}${dirty} dirty${NC}"
      fi

      [ -z "$status_parts" ] && status_parts="${GREEN}clean${NC}"

      echo -e "  $label $branch_info  $status_parts"
    done
    echo ""
    ;;

  status)
    phase "Git status across all repos"

    for repo_dir in "${REPOS[@]}"; do
      name=$(basename "$repo_dir")
      [[ "$repo_dir" == *"calytics-shared-modules"* ]] && name="shared/$name"

      current=$(cd "$repo_dir" && git branch --show-current 2>/dev/null)
      dirty=$(cd "$repo_dir" && git status --porcelain 2>/dev/null)

      label=$(printf "%-35s" "$name")
      branch_info="${CYAN}${current}${NC}"

      if [ -z "$dirty" ]; then
        echo -e "  $label $branch_info  ${GREEN}clean${NC}"
      else
        dirty_count=$(echo "$dirty" | wc -l)
        echo -e "  $label $branch_info  ${RED}${dirty_count} changes${NC}"
      fi
    done
    echo ""
    ;;

  *)
    fail "Unknown: cal git $subcmd (try: fetch, status)"
    ;;
esac
