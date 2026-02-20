#!/usr/bin/env bash
# spun.sh — Config Fix Script
# Fixes the broken claude-max config from the old installer
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}→${RESET} $*"; }
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }

echo ""
echo -e "${BOLD}${CYAN}  spun.sh — Config Fix${RESET}"
echo "────────────────────────────────────────────"
echo ""

CONFIG="$HOME/.openclaw/openclaw.json"

# Step 1: Extract bot token from broken config
info "Reading your existing config..."
BOT_TOKEN=$(python3 -c "
import json, sys
try:
    with open('$CONFIG') as f:
        c = json.load(f)
    tok = c.get('channels',{}).get('telegram',{}).get('accounts',{}).get('default',{}).get('botToken','')
    if tok:
        print(tok)
    else:
        sys.exit(1)
except Exception as e:
    sys.exit(1)
" 2>/dev/null) || true

if [[ -z "$BOT_TOKEN" ]]; then
  warn "Could not find your Telegram bot token in the existing config."
  read -p "Paste your Telegram bot token (from BotFather): " BOT_TOKEN
  BOT_TOKEN="$(echo "$BOT_TOKEN" | tr -d '[:space:]')"
fi

success "Bot token found"

# Step 2: Backup broken config
cp "$CONFIG" "${CONFIG}.broken-bak" 2>/dev/null || true
info "Backed up old config to openclaw.json.broken-bak"

# Step 3: Generate setup-token and configure auth
info "Generating Claude setup-token..."
SETUP_TOKEN=$(claude setup-token 2>/dev/null || echo "")

if [[ -n "$SETUP_TOKEN" ]]; then
  echo "$SETUP_TOKEN" | openclaw models auth paste-token --provider anthropic 2>/dev/null && \
    success "Claude auth configured" || \
    warn "Could not auto-configure auth — continuing anyway"
else
  warn "Could not generate setup-token. Try running 'claude auth login' first."
fi

# Step 4: Write fixed config
WORKSPACE_DIR="$HOME/.openclaw/workspace"
mkdir -p "$WORKSPACE_DIR"

python3 - "$BOT_TOKEN" "$WORKSPACE_DIR" << 'PYEOF'
import json, sys, os

bot_token = sys.argv[1]
workspace = sys.argv[2]
home = os.path.expanduser("~")

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

config_path = f"{home}/.openclaw/openclaw.json"
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
print(f"Config written to {config_path}")
PYEOF

success "Config fixed!"

# Step 5: Start gateway
info "Starting OpenClaw..."
openclaw gateway stop 2>/dev/null || true
sleep 2
openclaw gateway start 2>/dev/null || openclaw gateway install && openclaw gateway start

echo ""
echo "────────────────────────────────────────────"
echo -e "${GREEN}${BOLD}  Fixed! Your agent should be live now. 🎉${RESET}"
echo "────────────────────────────────────────────"
echo ""
echo "  Open Telegram and message your bot to test it."
echo "  Need help? Message @spunsupport_bot"
echo ""
