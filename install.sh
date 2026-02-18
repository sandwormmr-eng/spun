#!/usr/bin/env bash
# spun.sh — OpenClaw + Claude Max Setup
# https://spun.sh
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}→${RESET} $*"; }
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
error()   { echo -e "${RED}✗${RESET} $*"; exit 1; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ███████╗██████╗ ██╗   ██╗███╗   ██╗"
echo "  ██╔════╝██╔══██╗██║   ██║████╗  ██║"
echo "  ███████╗██████╔╝██║   ██║██╔██╗ ██║"
echo "  ╚════██║██╔═══╝ ██║   ██║██║╚██╗██║"
echo "  ███████║██║     ╚██████╔╝██║ ╚████║"
echo "  ╚══════╝╚═╝      ╚═════╝ ╚═╝  ╚═══╝"
echo -e "${RESET}"
echo -e "  ${BOLD}Your AI agent. Set up in minutes.${RESET}"
echo -e "  spun.sh\n"
echo "────────────────────────────────────────────"

# ─── OS Check ─────────────────────────────────────────────────────────────────
header "Checking your system..."
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM="macOS" ;;
  Linux)  PLATFORM="Linux" ;;
  *)      error "Windows detected. Please use the PowerShell installer instead: spun.sh/windows" ;;
esac
success "Platform: $PLATFORM"

# ─── Node.js ──────────────────────────────────────────────────────────────────
header "Step 1/5 — Node.js"
NODE_MIN=22
install_node() {
  if [[ "$PLATFORM" == "macOS" ]]; then
    if ! command -v brew &>/dev/null; then
      info "Installing Homebrew first..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    info "Installing Node.js via Homebrew..."
    brew install node@22
    brew link node@22 --force --overwrite 2>/dev/null || true
  else
    info "Installing Node.js via NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
  fi
}

if command -v node &>/dev/null; then
  NODE_VER=$(node -e "process.stdout.write(process.version.slice(1).split('.')[0])")
  if [[ "$NODE_VER" -ge "$NODE_MIN" ]]; then
    success "Node.js v$(node -v | tr -d 'v') already installed"
  else
    warn "Node.js v$NODE_VER found but v$NODE_MIN+ required. Upgrading..."
    install_node
  fi
else
  info "Node.js not found. Installing..."
  install_node
fi

# ─── OpenClaw ─────────────────────────────────────────────────────────────────
header "Step 2/5 — OpenClaw"
if command -v openclaw &>/dev/null; then
  info "OpenClaw found. Updating to latest..."
  npm update -g openclaw
  success "OpenClaw updated"
else
  info "Installing OpenClaw..."
  npm install -g openclaw
  success "OpenClaw installed"
fi

# ─── Claude Code CLI ──────────────────────────────────────────────────────────
header "Step 3/5 — Claude Code CLI"
if command -v claude &>/dev/null; then
  success "Claude CLI already installed"
else
  info "Installing Claude Code CLI..."
  npm install -g @anthropic-ai/claude-code
  success "Claude CLI installed"
fi

echo ""
echo -e "${BOLD}${YELLOW}ACTION REQUIRED — Claude Login${RESET}"
echo "────────────────────────────────────────────"
echo "Your browser will open. Log in with your Claude.ai account."
echo "This is how your AI agent uses your Claude Max subscription."
echo "(Close the browser tab after you see 'Authorization successful')"
echo "────────────────────────────────────────────"
echo ""
read -p "Press ENTER when ready to log in..."
claude auth login
success "Claude authenticated"

# ─── Claude Max API Proxy ─────────────────────────────────────────────────────
header "Step 4/5 — Claude Max Bridge"
if command -v claude-max-api &>/dev/null; then
  success "Claude Max bridge already installed"
else
  info "Installing Claude Max bridge..."
  npm install -g claude-max-api-proxy
  success "Claude Max bridge installed"
fi

# Auto-start on login (macOS)
if [[ "$PLATFORM" == "macOS" ]]; then
  PLIST="$HOME/Library/LaunchAgents/com.claude-max-api.plist"
  if [[ ! -f "$PLIST" ]]; then
    info "Setting Claude Max bridge to start automatically..."
    NODE_PATH="$(which node)"
    PROXY_PATH="$(npm root -g)/claude-max-api-proxy/dist/server/standalone.js"
    cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.claude-max-api</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE_PATH</string>
    <string>$PROXY_PATH</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
    launchctl bootstrap gui/$(id -u) "$PLIST" 2>/dev/null || true
    success "Bridge configured to start on login"
  fi
  # Start it now if not running
  if ! curl -sf http://localhost:3456/health &>/dev/null; then
    info "Starting Claude Max bridge..."
    launchctl kickstart gui/$(id -u)/com.claude-max-api 2>/dev/null || claude-max-api &
    sleep 2
  fi
fi

# ─── OpenClaw Config ──────────────────────────────────────────────────────────
header "Step 5/5 — Configuring OpenClaw"
CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/config.json5"
mkdir -p "$CONFIG_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
  cat > "$CONFIG_FILE" << 'EOF'
{
  env: {
    OPENAI_API_KEY: "not-needed",
    OPENAI_BASE_URL: "http://localhost:3456/v1",
  },
  agents: {
    defaults: {
      model: { primary: "openai/claude-sonnet-4" },
    },
  },
}
EOF
  success "OpenClaw configured"
else
  warn "Config already exists — skipping. (Edit $CONFIG_FILE manually if needed)"
fi

# ─── Start OpenClaw ───────────────────────────────────────────────────────────
info "Starting OpenClaw gateway..."
openclaw gateway start 2>/dev/null || true

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────"
echo -e "${GREEN}${BOLD}  You're live. 🎉${RESET}"
echo "────────────────────────────────────────────"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo "  1. Open Telegram and message your OpenClaw bot"
echo "  2. Or run: openclaw status"
echo "  3. Full setup guide: spun.sh/guide"
echo ""
echo -e "  ${CYAN}Need help? spun.sh/support${RESET}"
echo ""
