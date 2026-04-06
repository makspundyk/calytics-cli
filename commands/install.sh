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
#   - Registers `cal` in ~/.bashrc and sources it immediately
#   - Fixes file permissions across the project
#   - Configures git author for every repo

set -euo pipefail

# ── Resolve paths ────────────────────────────────────────────────
if [ -n "${CAL_ROOT:-}" ]; then
  SCRIPT_DIR="$CAL_ROOT"
  PROJECT_DIR="$CAL_PROJECT"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
CLI_DIRNAME="$(basename "$SCRIPT_DIR")"

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
# 1. Register CLI + fix permissions (first — so `cal` works immediately)
# ══════════════════════════════════════════════════════════════════
phase "1/8  Register CLI"

# Fix permissions on all scripts
info "Fixing file permissions..."
find "$PROJECT_DIR" -name "*.sh" -type f -exec chmod +x {} + 2>/dev/null
find "$SCRIPT_DIR" -name "*.sh" -type f -exec chmod +x {} + 2>/dev/null
for repo_scripts in "$PROJECT_DIR"/calytics-*/scripts; do
  [ -d "$repo_scripts" ] && find "$repo_scripts" -name "*.sh" -type f -exec chmod +x {} + 2>/dev/null
done
ok "File permissions fixed"

# Register cal in ~/.bashrc
BASHRC="$HOME/.bashrc"
CAL_SOURCE_LINE="source \"$SCRIPT_DIR/cal.sh\" 2>/dev/null"

if grep -qF "$CLI_DIRNAME/cal.sh" "$BASHRC" 2>/dev/null; then
  ok "cal CLI already in ~/.bashrc"
else
  info "Adding cal CLI to ~/.bashrc..."
  echo "" >> "$BASHRC"
  echo "# Calytics CLI" >> "$BASHRC"
  echo "$CAL_SOURCE_LINE" >> "$BASHRC"
  ok "cal CLI added to ~/.bashrc"
fi

# Source it now so `cal` is available for the rest of this script
source "$SCRIPT_DIR/cal.sh" 2>/dev/null || true
ok "cal CLI loaded in current shell"

# Ensure .env and .env.local exist in the project root (next to calytics-cli/)
ENV_DIR="$SCRIPT_DIR/env"
if [ ! -f "$PROJECT_DIR/.env.local" ]; then
  info "Creating .env.local from template..."
  cp "$ENV_DIR/local.env" "$PROJECT_DIR/.env.local"
  ok ".env.local created"
else
  ok ".env.local exists"
fi

if [ ! -f "$PROJECT_DIR/.env" ]; then
  info "Creating .env (auto-detecting WSL IP)..."
  WSL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
  sed "s/__WSL_IP__/$WSL_IP/g" "$ENV_DIR/dot-env.template" > "$PROJECT_DIR/.env"
  ok ".env created (IP: $WSL_IP)"
else
  ok ".env exists"
fi

# ══════════════════════════════════════════════════════════════════
# 2. System packages (apt)
# ══════════════════════════════════════════════════════════════════
phase "2/8  System packages"

PKGS=(
  git curl wget jq openssl lsof zip unzip
  build-essential ca-certificates gnupg
  software-properties-common apt-transport-https
)

MISSING=()
for pkg in "${PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null || MISSING+=("$pkg")
done
has pgrep || MISSING+=(procps)

if [ ${#MISSING[@]} -eq 0 ]; then
  ok "All system packages present"
else
  info "Installing: ${MISSING[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y -qq "${MISSING[@]}"
  ok "System packages installed"
fi

# ══════════════════════════════════════════════════════════════════
# 3. Docker
# ══════════════════════════════════════════════════════════════════
phase "3/8  Docker"

if has docker; then
  ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+')"
else
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  ok "Docker installed (log out and back in for group changes)"
fi

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
# 4. Node.js 22 (via nvm)
# ══════════════════════════════════════════════════════════════════
phase "4/8  Node.js"

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [ ! -d "$NVM_DIR" ]; then
  info "Installing nvm..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  ok "nvm installed"
fi

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
# 5. AWS CLI v2
# ══════════════════════════════════════════════════════════════════
phase "5/8  AWS CLI"

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
# 6. Terraform
# ══════════════════════════════════════════════════════════════════
phase "6/8  Terraform"

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
# 7. Global npm tools + snap packages
# ══════════════════════════════════════════════════════════════════
phase "7/8  Dev tools"

if has serverless; then
  ok "Serverless $(serverless --version 2>/dev/null | head -1)"
else
  info "Installing Serverless Framework..."
  npm install -g serverless
  ok "Serverless installed"
fi

if has claude; then
  ok "Claude Code installed"
else
  info "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code 2>/dev/null && ok "Claude Code installed" || warn "Claude Code install failed (non-fatal)"
fi

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
  sudo snap install ngrok 2>/dev/null && ok "ngrok installed" || warn "ngrok install failed (non-fatal)"
fi

# ══════════════════════════════════════════════════════════════════
# 8. Pre-pull Docker images (so first `cal start` is fast)
# ══════════════════════════════════════════════════════════════════
phase "8/9  Docker images"

IMAGES=(
  "ghcr.io/tarampampam/webhook-tester:2"
  "aaronshaf/dynamodb-admin"
  "localstack/localstack:3.8"
  "postgres:16-alpine"
  "redocly/redoc:latest"
)

for img in "${IMAGES[@]}"; do
  if docker image inspect "$img" &>/dev/null; then
    ok "$img cached"
  else
    info "Pulling $img..."
    docker pull "$img" 2>&1 | tail -1
    ok "$img pulled"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 9. Git authors
# ══════════════════════════════════════════════════════════════════
phase "9/9  Git authors"

AUTHOR_NAME="Maksym Pundyk"
AUTHOR_EMAIL_COMPANY="m.pundyk@calytics.io"
AUTHOR_EMAIL_CLI="maksym.p@ideainyou.com"

for repo_dir in "$PROJECT_DIR"/*/; do
  [ ! -d "$repo_dir/.git" ] && continue
  repo_name=$(basename "$repo_dir")

  if [ "$repo_name" = "$CLI_DIRNAME" ]; then
    (cd "$repo_dir" && git config user.name "$AUTHOR_NAME" && git config user.email "$AUTHOR_EMAIL_CLI")
    ok "$repo_name → $AUTHOR_EMAIL_CLI"
  else
    (cd "$repo_dir" && git config user.name "$AUTHOR_NAME" && git config user.email "$AUTHOR_EMAIL_COMPANY")
    ok "$repo_name → $AUTHOR_EMAIL_COMPANY"
  fi
done

if [ -d "$PROJECT_DIR/calytics-shared-modules" ]; then
  for mod_dir in "$PROJECT_DIR/calytics-shared-modules"/*/; do
    [ ! -d "$mod_dir/.git" ] && continue
    mod_name=$(basename "$mod_dir")
    (cd "$mod_dir" && git config user.name "$AUTHOR_NAME" && git config user.email "$AUTHOR_EMAIL_COMPANY")
    ok "shared/$mod_name → $AUTHOR_EMAIL_COMPANY"
  done
fi

# ══════════════════════════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}  Setup complete!${NC}"
echo ""
echo -e "  ${CYAN}cal${NC} is ready. Try:"
echo -e "    ${CYAN}cal help${NC}          — see all commands"
echo -e "    ${CYAN}cal deploy${NC}        — start local environment"
echo -e "    ${CYAN}cal status${NC}        — check what's running"
echo ""
