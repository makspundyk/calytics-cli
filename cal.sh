#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# Calytics CLI (cal)
#
# Source this file in your ~/.bashrc:
#   source /path/to/calytics/calytics-cli/cal.sh
#
# Then use from anywhere:
#   cal start be
#   cal restart a2a
#   cal seed api-keys
#   cal help
# ═══════════════════════════════════════════════════════════════════

# Resolve paths from this file's location (no hardcoded usernames)
export CAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CAL_PROJECT="$(cd "$CAL_ROOT/.." && pwd)"

cal() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true

  local script="$CAL_ROOT/commands/${cmd}.sh"
  if [ ! -f "$script" ]; then
    echo -e "\033[0;31mUnknown command:\033[0m $cmd"
    echo ""
    echo "Run 'cal help' for available commands."
    return 1
  fi

  # Source shared libs into the command's environment
  export CAL_ROOT CAL_PROJECT
  bash -c "
    source '$CAL_ROOT/lib/colors.sh'
    source '$CAL_ROOT/lib/services.sh'
    source '$CAL_ROOT/lib/helpers.sh'
    source '$CAL_ROOT/env/defaults.sh'
    source '$script' \"\$@\"
  " -- "$@"
}

# Tab completion
_cal_completions() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"

  if [ "$COMP_CWORD" -eq 1 ]; then
    # Complete command names from commands/ directory
    local cmds=$(ls "$CAL_ROOT/commands/"*.sh 2>/dev/null | xargs -I{} basename {} .sh)
    COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
  elif [ "$COMP_CWORD" -eq 2 ]; then
    case "$prev" in
      start|stop|restart|logs)
        COMPREPLY=($(compgen -W "be a2a rs admin fe docs dynamo-gui all" -- "$cur"))
        ;;
      seed)
        COMPREPLY=($(compgen -W "all secrets queues client admins webhooks plans api-keys ses a2a-tables" -- "$cur"))
        ;;
      build)
        COMPREPLY=($(compgen -W "shared shims be admin a2a" -- "$cur"))
        ;;
      migrate)
        COMPREPLY=($(compgen -W "run revert dynamo" -- "$cur"))
        ;;
      sync)
        COMPREPLY=($(compgen -W "finapi qonto terraform" -- "$cur"))
        ;;
      deploy)
        COMPREPLY=($(compgen -W "--services-only --infra-only --skip= --env=" -- "$cur"))
        ;;
      help)
        local cmds=$(ls "$CAL_ROOT/commands/"*.sh 2>/dev/null | xargs -I{} basename {} .sh)
        COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
        ;;
    esac
  fi
}
complete -F _cal_completions cal
