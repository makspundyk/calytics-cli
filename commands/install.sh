#!/bin/bash
# cal install
# Bootstrap a fresh Linux (Ubuntu/Debian) with all tools needed for Calytics development.
# Safe to re-run — skips already-installed packages.
#
# What it installs:
#   System:     git, curl, jq, openssl, lsof, zip, unzip, build-essential
#   Docker:     docker, docker-compose-plugin
#   Node.js:    Node 22 via nvm
#   AWS CLI:    aws (v2)
#   Terraform:  terraform (HashiCorp APT repo)
#   Serverless: serverless (npm global)
#   Snap tools: snapd, ngrok
#   Claude:     claude-code (npm global)
#
# Also:
#   - Fixes file permissions across the project
#   - Registers `cal` in ~/.bashrc if not already present

set -euo pipefail

# ── Resolve paths ────────────────────────────────────────────────
if [ -n "${CAL_ROOT:-}" ]; then
  SCRIPT_DIR="$CAL_ROOT"
  PROJECT_DIR="$CAL_PROJECT"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# ── Colors (inline — lib may not be sourced on first run) ────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
phase() { echo -e "\n${BOLD}$*${NC}\n"; }

has() { command -v "$1" &>/dev/null; }

echo ""
echo -e "${BOLD}  ╔═══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║       Calytics Development Setup          ║${NC}"
echo -e "${BOLD}  ╚═══════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════
# 1. System packages (apt)
# ══════════════════════════════════════════════════════════════════
phase "1/7  System packages"

PKGS=(
  git curl wget jq openssl lsof zip unzip
  build-essential ca-certificates gnupg
  software-properties-common apt-transport-https
  pgrep-tools
)

# Filter to only missing packages
MISSING=()
for pkg in "${PKGS[@]}"; do
  # pgrep-tools is virtual — check the binary instead
  if [ "$pkg" = "pgrep-tools" ]; then
    has pgrep || MISSING+=(procps)
  elif ! dpkg -s "$pkg" &>/dev/null; then
    MISSING+=("$pkg")
  fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
  ok "All system packages present"
else
  info "Installing: ${MISSING[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y -qq "${MISSING[@]}"
  ok "System packages installed"
fi

# ══════════════════════════════════════════════════════════════════
# 2. Docker
# ══════════════════════════════════════════════════════════════════
phase "2/7  Docker"

if has docker; then
  ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+')"
else
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  ok "Docker installed (you may need to log out and back in for group changes)"
fi

# Docker Compose plugin
if docker compose version &>/dev/null; then
  ok "Docker Compose $(docker compose version --short 2>/dev/null)"
else
  info "Installing Docker Compose plugin..."
  sudo apt-get install -y -qq docker-compose-plugin 2>/dev/null || {
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    sudo curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  }
  ok "Docker Compose installed"
fi

# ══════════════════════════════════════════════════════════════════
# 3. Node.js 22 (via nvm)
# ══════════════════════════════════════════════════════════════════
phase "3/7  Node.js"

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [ ! -d "$NVM_DIR" ]; then
  info "Installing nvm..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  ok "nvm installed"
fi

# Source nvm
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

if has node && node -v | grep -q "^v22"; then
  ok "Node.js $(node -v)"
else
  info "Installing Node.js 22..."
  nvm install 22
  nvm alias default 22
  nvm use 22
  ok "Node.js $(node -v)"
fi

# ══════════════════════════════════════════════════════════════════
# 4. AWS CLI v2
# ══════════════════════════════════════════════════════════════════
phase "4/7  AWS CLI"

if has aws; then
  ok "AWS CLI $(aws --version 2>&1 | head -1)"
else
  info "Installing AWS CLI v2..."
  TMP=$(mktemp -d)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$TMP/awscli.zip"
  unzip -q "$TMP/awscli.zip" -d "$TMP"
  sudo "$TMP/aws/install"
  rm -rf "$TMP"
  ok "AWS CLI installed"
fi

# ══════════════════════════════════════════════════════════════════
# 5. Terraform
# ══════════════════════════════════════════════════════════════════
phase "5/7  Terraform"

if has terraform; then
  ok "Terraform $(terraform version -json 2>/dev/null | jq -r .terraform_version 2>/dev/null || terraform version | head -1)"
else
  info "Installing Terraform..."
  wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq terraform
  ok "Terraform installed"
fi

# ══════════════════════════════════════════════════════════════════
# 6. Global npm tools + snap packages
# ══════════════════════════════════════════════════════════════════
phase "6/7  Dev tools"

# Serverless Framework
if has serverless; then
  ok "Serverless $(serverless --version 2>/dev/null | head -1)"
else
  info "Installing Serverless Framework..."
  npm install -g serverless
  ok "Serverless installed"
fi

# Claude Code
if has claude; then
  ok "Claude Code installed"
else
  info "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code 2>/dev/null && ok "Claude Code installed" || warn "Claude Code install failed (non-fatal)"
fi

# Snap + ngrok
if has snap; then
  ok "snapd present"
else
  info "Installing snapd..."
  sudo apt-get install -y -qq snapd
  ok "snapd installed"
fi

if has ngrok; then
  ok "ngrok present"
else
  info "Installing ngrok via snap..."
  sudo snap install ngrok 2>/dev/null && ok "ngrok installed" || warn "ngrok install failed (non-fatal — may need 'snap connect ngrok:network')"
fi

# ══════════════════════════════════════════════════════════════════
# 7. Project setup (permissions + bashrc)
# ══════════════════════════════════════════════════════════════════
phase "7/7  Project setup"

# Fix permissions on all scripts
info "Fixing file permissions..."
find "$PROJECT_DIR" -name "*.sh" -type f -exec chmod +x {} + 2>/dev/null
find "$PROJECT_DIR/cli" -name "*.sh" -type f -exec chmod +x {} + 2>/dev/null
# Also fix scripts inside repos
for repo_scripts in "$PROJECT_DIR"/calytics-*/scripts; do
  [ -d "$repo_scripts" ] && find "$repo_scripts" -name "*.sh" -type f -exec chmod +x {} + 2>/dev/null
done
ok "File permissions fixed"

# Register cal in ~/.bashrc
BASHRC="$HOME/.bashrc"
CAL_SOURCE_LINE="source \"$SCRIPT_DIR/cal.sh\" 2>/dev/null"

if grep -qF "calytics-cli/cal.sh" "$BASHRC" 2>/dev/null; then
  ok "cal CLI already in ~/.bashrc"
else
  info "Adding cal CLI to ~/.bashrc..."
  echo "" >> "$BASHRC"
  echo "# Calytics CLI" >> "$BASHRC"
  echo "$CAL_SOURCE_LINE" >> "$BASHRC"
  ok "cal CLI added to ~/.bashrc"
fi

# ══════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}  Setup complete!${NC}"
echo ""
echo -e "  Open a new terminal, then run:"
echo -e "    ${CYAN}cal help${NC}          — see all commands"
echo -e "    ${CYAN}cal deploy${NC}        — start local environment"
echo -e "    ${CYAN}cal status${NC}        — check what's running"
echo ""
