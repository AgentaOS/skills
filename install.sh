#!/usr/bin/env bash
set -e

# AgentaOS CLI Installer
# Usage: curl -fsSL https://agentaos.ai/install | bash
# Works in terminals (human) and Claude Code (agent).

REQUIRED_NODE=20

# Colors only if terminal
if [ -t 1 ]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'
else
    GREEN=''; RED=''; DIM=''; BOLD=''; NC=''
fi

info() { echo -e "  ${GREEN}OK${NC}: $1"; }
fail() { echo -e "  ${RED}ERROR${NC}: $1"; exit 1; }

echo ""
echo "AgentaOS installer"
echo ""

# Check Node.js
if ! command -v node &>/dev/null; then
    fail "Node.js not found. Install v${REQUIRED_NODE}+ first: curl -fsSL https://fnm.vercel.app/install | bash && fnm install ${REQUIRED_NODE} && fnm use ${REQUIRED_NODE}"
fi

NODE_MAJOR=$(node -e "process.stdout.write(process.version.split('.')[0].slice(1))")
if [ "$NODE_MAJOR" -lt "$REQUIRED_NODE" ]; then
    fail "Node.js v${REQUIRED_NODE}+ required (found $(node --version)). Run: fnm install ${REQUIRED_NODE} && fnm use ${REQUIRED_NODE}"
fi
info "Node.js $(node --version)"

# Install
npm install -g agentaos@latest --loglevel=error
echo ""

# Verify
if command -v agenta &>/dev/null; then
    info "agenta $(agenta --version 2>/dev/null || echo 'installed')"
else
    fail "Installed but agenta not in PATH. Restart shell and retry."
fi

echo ""
echo "Next steps:"
echo "  agenta login              # sign in via browser"
echo "  agenta status             # account overview"
echo "  agenta pay checkout -a 50 # create a payment"
echo ""
