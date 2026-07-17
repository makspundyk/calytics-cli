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
# Works when sourced from bash (BASH_SOURCE) or zsh (%x prompt expansion)
if [ -n "${BASH_SOURCE:-}" ]; then
  _CAL_SELF="${BASH_SOURCE[0]}"
else
  _CAL_SELF="${(%):-%x}"
fi
export CAL_ROOT="$(cd "$(dirname "$_CAL_SELF")" && pwd)"
export CAL_PROJECT="$(cd "$CAL_ROOT/.." && pwd)"
unset _CAL_SELF

# The registry uses associative arrays (bash >= 4). macOS ships bash 3.2
# forever, so resolve a modern bash explicitly instead of trusting PATH.
_cal_find_bash() {
  local b
  for b in "${CAL_BASH:-}" "$(command -v bash 2>/dev/null)" \
           "$HOME/bin/bash" /opt/homebrew/bin/bash /usr/local/bin/bash /bin/bash; do
    [ -n "$b" ] && [ -x "$b" ] || continue
    if "$b" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ]' 2>/dev/null; then
      echo "$b"
      return 0
    fi
  done
  return 1
}
CAL_BASH="$(_cal_find_bash)" || CAL_BASH=""
export CAL_BASH

cal() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true

  if [ -z "$CAL_BASH" ]; then
    echo -e "\033[0;31mcal needs bash >= 4\033[0m (macOS ships 3.2). Install one, e.g.: brew install bash"
    return 1
  fi

  local script="$CAL_ROOT/commands/${cmd}.sh"
  if [ ! -f "$script" ]; then
    echo -e "\033[0;31mUnknown command:\033[0m $cmd"
    echo ""
    echo "Run 'cal help' for available commands."
    return 1
  fi

  # Source shared libs into the command's environment
  export CAL_ROOT CAL_PROJECT
  "$CAL_BASH" -c "
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
      restart|logs|open)
        COMPREPLY=($(compgen -W "be a2a cp rs rs-api admin fe docs dynamo-gui webhooks finapi-mock all" -- "$cur"))
        ;;
      start)
        COMPREPLY=($(compgen -W "be a2a cp rs rs-api admin fe docs dynamo-gui webhooks finapi-mock all infra" -- "$cur"))
        ;;
      stop)
        COMPREPLY=($(compgen -W "be a2a cp rs rs-api admin fe docs dynamo-gui webhooks finapi-mock infra" -- "$cur"))
        ;;
      seed)
        COMPREPLY=($(compgen -W "all secrets queues client admins webhooks plans api-keys ses a2a-tables a2a-payments cross-product-tables dg-data" -- "$cur"))
        ;;
      callbacks)
        COMPREPLY=($(compgen -W "drain" -- "$cur"))
        ;;
      build)
        COMPREPLY=($(compgen -W "shared shims be admin a2a cp docs" -- "$cur"))
        ;;
      git)
        COMPREPLY=($(compgen -W "fetch status" -- "$cur"))
        ;;
      migrate)
        COMPREPLY=($(compgen -W "run revert dynamo" -- "$cur"))
        ;;
      sync)
        COMPREPLY=($(compgen -W "finapi qonto terraform" -- "$cur"))
        ;;
      rs)
        COMPREPLY=($(compgen -W "stream api" -- "$cur"))
        ;;
      deploy)
        COMPREPLY=($(compgen -W "--services-only --infra-only --skip= --env=" -- "$cur"))
        ;;
      help)
        local cmds=$(ls "$CAL_ROOT/commands/"*.sh 2>/dev/null | xargs -I{} basename {} .sh)
        COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
        ;;
    esac
  elif [ "$COMP_CWORD" -eq 3 ]; then
    local cmd="${COMP_WORDS[1]}"
    case "$cmd" in
      rs)
        COMPREPLY=($(compgen -W "dev sandbox --source --history" -- "$cur"))
        ;;
    esac
  fi
}
# zsh: load bash-compatible completion shims first
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X compinit && compinit -u
  autoload -U +X bashcompinit && bashcompinit
fi
complete -F _cal_completions cal 2>/dev/null || true

# When EXECUTED directly (`./cal.sh start infra`, `bash cal.sh seed a2a-tables`)
# rather than sourced, dispatch to the cal function so the CLI works either way.
# Executed: the shebang runs this under bash, so BASH_SOURCE[0] == $0 → dispatch.
# Sourced (into a bash or zsh shell): BASH_SOURCE[0] != $0 (or unset under zsh),
# so this never fires on `source cal.sh` — it only defines the function, as before.
if [ -n "${BASH_SOURCE:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cal "$@"
fi
