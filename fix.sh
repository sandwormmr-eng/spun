#!/usr/bin/env bash
# spun.sh — Recovery Script
# Fixes broken installs, crashed gateways, expired auth, and bad configs
# Run with: bash <(curl -fsSL https://spun.sh/fix.sh)
exec < /dev/tty 2>/dev/null || true
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}→${RESET} $*"; }
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
fail()    { echo -e "${RED}✗${RESET} $*"; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

echo ""
echo -e "${BOLD}${CYAN}  spun.sh — Recovery Tool${RESET}"
echo "────────────────────────────────────────────"
echo ""

mkdir -p "$HOME/.openclaw/logs"
CONFIG="$HOME/.openclaw/openclaw.json"
WORKSPACE_DIR="$HOME/.openclaw/workspace"

# ─── Step 1: Stop everything ──────────────────────────────────────────────────
header "Step 1 — Stopping existing processes..."
openclaw gateway stop 2>/dev/null || true
pkill -f "claude-max-api" 2>/dev/null || true
sleep 2
success "Processes stopped"

# ─── Step 2: Check Node.js ────────────────────────────────────────────────────
header "Step 2 — Node.js check..."
if command -v node &>/dev/null; then
  NODE_VER=$(node -e "process.stdout.write(process.version.slice(1).split('.')[0])")
  if [[ "$NODE_VER" -ge 22 ]]; then
    success "Node.js v$(node -v | tr -d 'v') OK"
  else
    warn "Node.js v$NODE_VER is too old (need v22+)."
    echo "  Run the full installer to upgrade: bash <(curl -fsSL https://spun.sh)"
    exit 1
  fi
else
  warn "Node.js not found. Run the full installer: bash <(curl -fsSL https://spun.sh)"
  exit 1
fi

# ─── Step 3: Verify packages ──────────────────────────────────────────────────
header "Step 3 — Checking packages..."
if ! command -v openclaw &>/dev/null; then
  info "OpenClaw missing — installing..."
  npm install -g openclaw
fi
success "OpenClaw: $(openclaw --version 2>/dev/null || echo 'installed')"

if ! command -v claude &>/dev/null; then
  info "Claude CLI missing — installing..."
  npm install -g @anthropic-ai/claude-code
fi
success "Claude CLI: installed"

# ─── Step 4: Claude auth ──────────────────────────────────────────────────────
header "Step 4 — Claude authentication..."
AUTH_OK=false
if claude auth status &>/dev/null 2>&1; then
  AUTH_OK=true
  success "Claude auth valid"
else
  warn "Claude auth expired or missing."
  echo ""
  echo "  Your browser will open — log in with your Claude.ai account."
  read -p "  Press ENTER to authenticate..."
  claude auth login && AUTH_OK=true
fi

# Re-link setup-token if auth is working
if [[ "$AUTH_OK" == "true" ]]; then
  info "Refreshing Claude setup-token..."
  SETUP_TOKEN=$(claude setup-token 2>/dev/null || echo "")
  if [[ -n "$SETUP_TOKEN" ]]; then
    echo "$SETUP_TOKEN" | openclaw models auth paste-token --provider anthropic 2>/dev/null && \
      success "Claude auth connected to OpenClaw" || \
      warn "Could not auto-link auth — gateway will try on startup"
  fi
fi

# ─── Step 5: Config check / repair ───────────────────────────────────────────
header "Step 5 — Config check..."

CONFIG_OK=false
if [[ -f "$CONFIG" ]]; then
  # Validate config has the essential fields
  VALID=$(python3 -c "
import json, sys
try:
  with open('$CONFIG') as f:
    c = json.load(f)
  has_model = bool(c.get('agents',{}).get('defaults',{}).get('model',{}).get('primary',''))
  has_tg = bool(c.get('channels',{}).get('telegram',{}).get('accounts',{}).get('default',{}).get('botToken',''))
  print('ok' if (has_model and has_tg) else 'bad')
except:
  print('bad')
" 2>/dev/null || echo "bad")

  if [[ "$VALID" == "ok" ]]; then
    success "Config looks good"
    CONFIG_OK=true
  else
    warn "Config is missing fields or malformed — repairing..."
  fi
fi

if [[ "$CONFIG_OK" != "true" ]]; then
  # Try to salvage existing bot token
  BOT_TOKEN=""
  if [[ -f "$CONFIG" ]]; then
    BOT_TOKEN=$(python3 -c "
import json, sys
try:
  with open('$CONFIG') as f:
    c = json.load(f)
  tok = c.get('channels',{}).get('telegram',{}).get('accounts',{}).get('default',{}).get('botToken','')
  print(tok) if tok else sys.exit(1)
except: sys.exit(1)
" 2>/dev/null || echo "")
  fi

  if [[ -n "$BOT_TOKEN" ]]; then
    info "Found existing bot token — will use it"
  else
    echo ""
    echo "  Couldn't find your Telegram bot token."
    echo "  Get it from @BotFather on Telegram (the token looks like: 1234567890:ABCDef...)"
    read -p "  Paste your bot token: " BOT_TOKEN
    BOT_TOKEN="$(echo "$BOT_TOKEN" | tr -d '[:space:]')"
  fi

  [[ -f "$CONFIG" ]] && cp "$CONFIG" "${CONFIG}.bak" 2>/dev/null && info "Backed up old config to openclaw.json.bak"
  mkdir -p "$WORKSPACE_DIR"

  python3 - "$BOT_TOKEN" "$WORKSPACE_DIR" << 'PYEOF'
import json, sys, os

bot_token = sys.argv[1]
workspace = sys.argv[2]

config = {
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-6",
        "fallbacks": ["anthropic/claude-sonnet-4-5"]
      },
      "models": {
        "anthropic/claude-sonnet-4-6": {},
        "anthropic/claude-sonnet-4-5": {}
      },
      "workspace": workspace
    }
  },
  "channels": {
    "telegram": {
      "enabled": True,
      "dmPolicy": "open",
      "groupPolicy": "disabled",
      "allowFrom": ["*"],
      "accounts": {
        "default": {
          "botToken": bot_token,
          "dmPolicy": "open",
          "allowFrom": ["*"],
          "groupPolicy": "disabled"
        }
      }
    }
  }
}

config_path = os.path.expanduser("~/.openclaw/openclaw.json")
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
print(f"  Config written to {config_path}")
PYEOF

  success "Config repaired"
fi

# ─── Step 6: Start gateway ────────────────────────────────────────────────────
header "Step 6 — Starting OpenClaw gateway..."
openclaw gateway install 2>/dev/null || true
openclaw doctor --fix 2>/dev/null || true
openclaw gateway start 2>/dev/null || true
sleep 3

GATEWAY_UP=false
for i in 1 2 3 4 5; do
  if openclaw gateway status 2>/dev/null | grep -q -i "running\|ok\|started\|online"; then
    GATEWAY_UP=true
    break
  fi
  sleep 2
done

echo ""
echo "────────────────────────────────────────────"

if [[ "$GATEWAY_UP" == "true" ]]; then
  echo -e "${GREEN}${BOLD}  All good. You're back online. 🎉${RESET}"
  echo "────────────────────────────────────────────"
  echo ""
  echo "  Open Telegram and message your bot to test it."
  echo -e "  Run ${BOLD}openclaw status${RESET} to confirm everything."
else
  ERR_LOG="$HOME/.openclaw/logs/gateway.err.log"
  fail "Gateway still not starting."
  echo "────────────────────────────────────────────"
  echo ""
  if [[ -f "$ERR_LOG" ]] && [[ -s "$ERR_LOG" ]]; then
    echo -e "${YELLOW}Gateway error log:${RESET}"
    tail -10 "$ERR_LOG" | sed 's/^/  /'
    echo ""
    echo "  Screenshot that error and send it to support."
  fi
  echo -e "  ${CYAN}https://t.me/spunsupport_bot${RESET}"
fi

echo ""
