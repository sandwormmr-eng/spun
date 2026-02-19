#!/usr/bin/env bash
# spun.sh — OpenClaw + Claude Max Setup
# https://spun.sh
# Fix stdin for curl | bash — must run BEFORE set -e so failure doesn't silently kill the script
exec < /dev/tty 2>/dev/null || true

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
header "Step 1/6 — Node.js"
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
header "Step 2/6 — OpenClaw"
if command -v openclaw &>/dev/null; then
  info "OpenClaw found. Updating to latest..."
  npm update -g openclaw 2>/dev/null || true
  success "OpenClaw updated: $(openclaw --version 2>/dev/null || echo 'ok')"
else
  info "Installing OpenClaw..."
  npm install -g openclaw
  success "OpenClaw installed"
fi

# ─── Claude Code CLI ──────────────────────────────────────────────────────────
header "Step 3/6 — Claude Code CLI"
if command -v claude &>/dev/null; then
  success "Claude CLI already installed: $(claude --version 2>/dev/null || echo 'ok')"
else
  info "Installing Claude Code CLI..."
  npm install -g @anthropic-ai/claude-code
  success "Claude CLI installed"
fi

echo ""
echo -e "${BOLD}${YELLOW}ACTION REQUIRED — Log in with Claude Max${RESET}"
echo "────────────────────────────────────────────"
echo "Your browser will open. Sign in with the Claude.ai account"
echo "that has your Claude Max subscription."
echo ""
echo "This is how your AI agent uses Claude — no API key needed."
echo "(Close the browser tab once you see 'Authorization successful')"
echo "────────────────────────────────────────────"
echo ""
read -p "Press ENTER when ready to log in..."
claude auth login || error "Claude login failed. Please try running 'claude auth login' manually."
success "Claude authenticated ✓"

# ─── Claude Max API Bridge ────────────────────────────────────────────────────
header "Step 4/6 — Claude Max Bridge"
if command -v claude-max-api &>/dev/null; then
  success "Claude Max bridge already installed"
else
  info "Installing Claude Max bridge..."
  npm install -g claude-max-api-proxy
  success "Claude Max bridge installed"
fi

# Start the bridge and set it to auto-start on login
BRIDGE_PORT=3456
start_bridge() {
  if curl -sf "http://localhost:${BRIDGE_PORT}/health" &>/dev/null; then
    success "Claude Max bridge already running on port $BRIDGE_PORT"
    return
  fi
  info "Starting Claude Max bridge on port $BRIDGE_PORT..."
  nohup claude-max-api > /tmp/claude-max-api.log 2>&1 &
  sleep 3
  if curl -sf "http://localhost:${BRIDGE_PORT}/health" &>/dev/null; then
    success "Claude Max bridge started"
  else
    warn "Bridge may still be starting — continuing anyway"
  fi
}

if [[ "$PLATFORM" == "macOS" ]]; then
  PLIST="$HOME/Library/LaunchAgents/com.claude-max-api.plist"
  if [[ ! -f "$PLIST" ]]; then
    info "Configuring bridge to start automatically on login..."
    NODE_BIN="$(which node)"
    PROXY_BIN="$(which claude-max-api 2>/dev/null || npm root -g)/claude-max-api-proxy/dist/server/standalone.js"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.claude-max-api</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProgramArguments</key>
  <array>
    <string>${NODE_BIN}</string>
    <string>${PROXY_BIN}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin</string>
  </dict>
  <key>StandardOutPath</key><string>/tmp/claude-max-api.log</string>
  <key>StandardErrorPath</key><string>/tmp/claude-max-api.log</string>
</dict>
</plist>
PLIST_EOF
    launchctl bootstrap gui/$(id -u) "$PLIST" 2>/dev/null || true
    success "Bridge configured to start on login"
  fi
  # Kick it now if not running
  if ! curl -sf "http://localhost:${BRIDGE_PORT}/health" &>/dev/null; then
    launchctl kickstart -k gui/$(id -u)/com.claude-max-api 2>/dev/null || true
    sleep 3
  fi
  start_bridge
else
  # Linux — use systemd if available, else just start it
  if command -v systemctl &>/dev/null && [[ -d "$HOME/.config/systemd/user" ]] 2>/dev/null; then
    UNIT_FILE="$HOME/.config/systemd/user/claude-max-api.service"
    if [[ ! -f "$UNIT_FILE" ]]; then
      mkdir -p "$HOME/.config/systemd/user"
      cat > "$UNIT_FILE" << UNIT_EOF
[Unit]
Description=Claude Max API Bridge
After=network.target

[Service]
ExecStart=$(which claude-max-api)
Restart=always
RestartSec=5
StandardOutput=append:/tmp/claude-max-api.log
StandardError=append:/tmp/claude-max-api.log

[Install]
WantedBy=default.target
UNIT_EOF
      systemctl --user enable claude-max-api.service 2>/dev/null || true
      systemctl --user start claude-max-api.service 2>/dev/null || true
      success "Bridge configured to start on login (systemd)"
    fi
  fi
  start_bridge
fi

# ─── Telegram Bot Setup ───────────────────────────────────────────────────────
header "Step 5/6 — Telegram Bot"
echo ""
echo -e "${BOLD}Create your Telegram bot (takes ~60 seconds):${RESET}"
echo ""
echo "  1. Open Telegram and search for ${BOLD}@BotFather${RESET}"
echo "  2. Send: ${CYAN}/newbot${RESET}"
echo "  3. Choose a display name (e.g. 'My Assistant')"
echo "  4. Choose a username ending in 'bot' (e.g. 'myassistant_bot')"
echo "  5. Copy the token BotFather gives you — looks like:"
echo "     ${YELLOW}1234567890:ABCDefGhIJKlmNoPQRsTUVwxyZ${RESET}"
echo ""

BOT_TOKEN=""
BOT_USERNAME="your_bot"

while true; do
  read -p "Paste your bot token here: " BOT_TOKEN
  BOT_TOKEN="$(echo "$BOT_TOKEN" | tr -d '[:space:]')"  # strip all whitespace
  [[ -z "$BOT_TOKEN" ]] && warn "Token can't be empty. Try again." && continue
  break
done

# Try to validate — but never block on it
info "Checking token with Telegram..."
VALIDATE_RESP=$(curl -s --max-time 8 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null || echo '{"ok":false}')
TG_OK=$(echo "$VALIDATE_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('ok',False)).lower())" 2>/dev/null || echo "false")

if [[ "$TG_OK" == "true" ]]; then
  BOT_USERNAME=$(echo "$VALIDATE_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['username'])" 2>/dev/null || echo "your_bot")
  success "Bot confirmed: @${BOT_USERNAME}"
else
  TG_DESC=$(echo "$VALIDATE_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('description','No response from Telegram'))" 2>/dev/null || echo "No response")
  warn "Could not verify token (${TG_DESC}) — writing it anyway."
  warn "If your bot doesn't respond after setup, double-check the token in BotFather."
fi

# ─── Configure OpenClaw ───────────────────────────────────────────────────────
header "Step 6/6 — Configuring OpenClaw"
OPENCLAW_DIR="$HOME/.openclaw"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
WORKSPACE_DIR="$OPENCLAW_DIR/workspace"

mkdir -p "$OPENCLAW_DIR"
mkdir -p "$WORKSPACE_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
  warn "Config already exists. Backing up to openclaw.json.bak"
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
fi

# Write the correct openclaw.json
python3 - "$BOT_TOKEN" "$WORKSPACE_DIR" << 'PYEOF'
import json, sys

bot_token = sys.argv[1]
workspace = sys.argv[2]

config = {
  "env": {
    "OPENAI_API_KEY": "not-needed",
    "OPENAI_BASE_URL": "http://localhost:3456/v1"
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "openai/claude-sonnet-4",
        "fallbacks": ["openai/claude-haiku-4"]
      },
      "models": {
        "openai/claude-sonnet-4": {},
        "openai/claude-haiku-4": {}
      },
      "workspace": workspace
    }
  },
  "gateway": {
    "mode": "local"
  },
  "channels": {
    "telegram": {
      "enabled": True,
      "dmPolicy": "open",
      "accounts": {
        "default": {
          "botToken": bot_token,
          "dmPolicy": "open",
          "allowFrom": ["*"]
        }
      }
    }
  }
}

config_path = f"{__import__('os').path.expanduser('~')}/.openclaw/openclaw.json"
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
print(f"Config written to {config_path}")
PYEOF

success "OpenClaw configured"

# ─── Start OpenClaw ───────────────────────────────────────────────────────────
info "Starting OpenClaw gateway..."
openclaw gateway start 2>/dev/null || true
sleep 2

# Quick sanity check
if openclaw gateway status 2>/dev/null | grep -q -i "running"; then
  GATEWAY_OK=true
else
  GATEWAY_OK=false
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────"
if [[ "$GATEWAY_OK" == "true" ]]; then
  echo -e "${GREEN}${BOLD}  You're live. 🎉${RESET}"
else
  echo -e "${YELLOW}${BOLD}  Almost there — one more step below.${RESET}"
fi
echo "────────────────────────────────────────────"
echo ""
echo -e "  ${BOLD}To start chatting:${RESET}"
echo -e "  1. Open Telegram and find ${CYAN}@${BOT_USERNAME}${RESET}"
echo "  2. Send it any message — your agent will respond"
echo ""

if [[ "$GATEWAY_OK" != "true" ]]; then
  echo -e "  ${YELLOW}Gateway didn't start automatically. Run:${RESET}"
  echo -e "  ${BOLD}openclaw gateway start${RESET}"
  echo ""
fi

echo -e "  ${BOLD}Useful commands:${RESET}"
echo "  openclaw gateway status   — check if running"
echo "  openclaw gateway restart  — restart the gateway"
echo "  openclaw status           — full system status"
echo ""
echo -e "  ${CYAN}Need help? spun.sh/support${RESET}"
echo ""
