#!/usr/bin/env bash
set -e

# AgentaOS CLI Installer
# Usage: curl -fsSL https://agentaos.ai/install | bash

REQUIRED_NODE=20
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✕${NC} $1"; exit 1; }

echo ""
echo -e "  ${BOLD}AgentaOS${NC} ${DIM}installer${NC}"
echo ""

# Check Node.js
if ! command -v node &>/dev/null; then
    fail "Node.js not found. Install v${REQUIRED_NODE}+:

    curl -fsSL https://fnm.vercel.app/install | bash
    fnm install ${REQUIRED_NODE}
    fnm use ${REQUIRED_NODE}

    Then re-run this installer."
fi

NODE_MAJOR=$(node -e "process.stdout.write(process.version.split('.')[0].slice(1))")
if [ "$NODE_MAJOR" -lt "$REQUIRED_NODE" ]; then
    fail "Node.js v${REQUIRED_NODE}+ required (found $(node --version)). Upgrade:

    fnm install ${REQUIRED_NODE}
    fnm use ${REQUIRED_NODE}"
fi
info "Node.js $(node --version)"

# Install
npm install -g agentaos@latest --loglevel=error
echo ""

# Verify
if command -v agenta &>/dev/null; then
    info "agenta $(agenta --version 2>/dev/null || echo 'installed')"
else
    fail "Installed but agenta not in PATH. Restart your shell and retry."
fi

echo ""
echo -e "  ${BOLD}Get started:${NC}"
echo -e "    agenta login              ${DIM}Sign in via browser${NC}"
echo -e "    agenta status             ${DIM}Account overview${NC}"
echo -e "    agenta pay checkout -a 50 ${DIM}Create a payment${NC}"
echo ""
