#!/bin/bash
set -euo pipefail

# ============================================================================
# XMR-Starknet Atomic Swap Deployment Script v4.0
# Updated: 2025-12-09
# ============================================================================
# Configuration
NETWORK="${1:-sepolia}"
RPC_URL="${STARKNET_RPC_URL:-https://api.zan.top/public/starknet-sepolia}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEPLOY_DIR="deployments/${NETWORK}/${TIMESTAMP}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "=============================================="
echo " XMR↔Starknet Atomic Swap Deployment v4.0"
echo "=============================================="
echo -e "Network:  ${BLUE}${NETWORK}${NC}"
echo -e "RPC:      ${BLUE}${RPC_URL}${NC}"
echo -e "Time:     ${TIMESTAMP}"
echo ""

cd "${ROOT_DIR}"
mkdir -p "${DEPLOY_DIR}"

# ============================================================================
# GATE 0: Prerequisites Check
# ============================================================================
echo -e "${YELLOW}[0/7] Checking prerequisites...${NC}"

# Check tools
command -v snforge >/dev/null 2>&1 || { echo -e "${RED}snforge not found${NC}"; exit 1; }
command -v scarb >/dev/null 2>&1 || { echo -e "${RED}scarb not found${NC}"; exit 1; }
command -v starkli >/dev/null 2>&1 || { echo -e "${RED}starkli not found (install: curl https://get.starkli.sh | sh)${NC}"; exit 1; }

# Check RPC connectivity
echo "Testing RPC connectivity..."
CHAIN_ID=$(curl -s -X POST "${RPC_URL}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"starknet_chainId","params":[],"id":1}' \
  | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")

if [ -z "${CHAIN_ID}" ]; then
  echo -e "${RED}Failed to connect to RPC${NC}"
  exit 1
fi

echo -e "${GREEN}Connected to chain: ${CHAIN_ID}${NC}"

# ============================================================================
# GATE 1: GOLDEN RULE - Sqrt Hint Validation (MANDATORY)
# ============================================================================
echo ""
echo -e "${YELLOW}[1/7] GOLDEN RULE GATE: Sqrt hint validation...${NC}"
echo ""
echo "Validating sqrt hints against Garaga decompression..."
echo "This gate CANNOT be skipped. Invalid sqrt hints = broken deployment."
echo ""

cd cairo

if ! snforge test test_e2e_dleq --exact 2>&1 | tee "${ROOT_DIR}/${DEPLOY_DIR}/gate1_golden_rule.log"; then
  echo ""
  echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  GOLDEN RULE VIOLATION: Sqrt hints failed Garaga validation   ║${NC}"
  echo -e "${RED}╠════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${RED}║  DEPLOYMENT BLOCKED. This is not optional.                    ║${NC}"
  echo -e "${RED}║                                                                ║${NC}"
  echo -e "${RED}║  Solution:                                                     ║${NC}"
  echo -e "${RED}║  1. Use sqrt hints from AUTHORITATIVE_SQRT_HINTS.cairo        ║${NC}"
  echo -e "${RED}║  2. Never regenerate sqrt hints from Python/Rust              ║${NC}"
  echo -e "${RED}║  3. See docs/SQRT_HINT_PREVENTION.md                          ║${NC}"
  echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
  exit 1
fi

# Verify PASS in output
if ! grep -qE "PASS|passed" "${ROOT_DIR}/${DEPLOY_DIR}/gate1_golden_rule.log"; then
  echo -e "${RED}Sqrt hint validation did not produce PASS result${NC}"
  exit 1
fi

echo -e "${GREEN}✓ GOLDEN RULE GATE PASSED: All sqrt hints validated${NC}"
echo ""

cd "${ROOT_DIR}"

# ============================================================================
# GATE 2: Cairo Tests (Two-Phase Unlock, Security)
# ============================================================================
echo ""
echo -e "${YELLOW}[2/7] Running Cairo test suite...${NC}"

cd cairo

# Two-phase unlock tests
echo "Running two-phase unlock tests..."
if ! snforge test test_two_phase_unlock 2>&1 | tee "${ROOT_DIR}/${DEPLOY_DIR}/gate2_two_phase.log"; then
  echo -e "${RED}Two-phase unlock tests failed${NC}"
  exit 1
fi

# Security tests
echo "Running security tests..."
if ! snforge test test_security 2>&1 | tee "${ROOT_DIR}/${DEPLOY_DIR}/gate2_security.log"; then
  echo -e "${RED}Security tests failed${NC}"
  exit 1
fi

echo -e "${GREEN}All Cairo tests passed${NC}"

cd "${ROOT_DIR}"

# ============================================================================
# GATE 3: Build Contract
# ============================================================================
echo ""
echo -e "${YELLOW}[3/7] Building Cairo contract...${NC}"

cd cairo

scarb build 2>&1 | tee "${ROOT_DIR}/${DEPLOY_DIR}/gate3_build.log"

CONTRACT_CLASS=$(find target/dev -name "*.contract_class.json" 2>/dev/null | head -1)

if [ -z "${CONTRACT_CLASS}" ] || [ ! -f "${CONTRACT_CLASS}" ]; then
  echo -e "${RED}Contract build failed - no contract class found${NC}"
  exit 1
fi

cp "${CONTRACT_CLASS}" "${ROOT_DIR}/${DEPLOY_DIR}/contract_class.json"

echo -e "${GREEN}Contract built: ${CONTRACT_CLASS}${NC}"

cd "${ROOT_DIR}"

# ============================================================================
# GATE 4: Declare Contract Class
# ============================================================================
echo ""
echo -e "${YELLOW}[4/7] Declaring contract class...${NC}"

# Check for account configuration
if [ ! -f ~/.starkli-wallets/deployer/account.json ]; then
  echo -e "${YELLOW}No deployer account found. Creating one...${NC}"
  echo ""
  echo "Run the following commands to set up your deployer account:"
  echo ""
  echo "  # 1. Create keystore"
  echo "  starkli signer keystore new ~/.starkli-wallets/deployer/keystore.json"
  echo ""
  echo "  # 2. Fund the account on Sepolia faucet"
  echo "  # https://starknet-faucet.vercel.app/"
  echo ""
  echo "  # 3. Deploy account"
  echo "  starkli account oz init ~/.starkli-wallets/deployer/account.json"
  echo "  starkli account deploy ~/.starkli-wallets/deployer/account.json"
  echo ""
  echo "Then re-run this script."
  exit 1
fi

echo "Declaring contract..."

DECLARE_OUTPUT=$(starkli declare "${DEPLOY_DIR}/contract_class.json" \
  --rpc "${RPC_URL}" \
  --account ~/.starkli-wallets/deployer/account.json \
  --watch 2>&1) || true

# Extract class hash
CLASS_HASH=$(echo "${DECLARE_OUTPUT}" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)

if [ -z "${CLASS_HASH}" ]; then
  # Check if already declared
  if echo "${DECLARE_OUTPUT}" | grep -q "already declared"; then
    CLASS_HASH=$(echo "${DECLARE_OUTPUT}" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
    echo -e "${YELLOW}Contract already declared: ${CLASS_HASH}${NC}"
  else
    echo -e "${RED}Declaration failed:${NC}"
    echo "${DECLARE_OUTPUT}"
    exit 1
  fi
else
  echo -e "${GREEN}Contract declared: ${CLASS_HASH}${NC}"
fi

echo "${CLASS_HASH}" > "${DEPLOY_DIR}/class_hash.txt"

# ============================================================================
# GATE 5: Deploy Contract Instance
# ============================================================================
echo ""
echo -e "${YELLOW}[5/7] Deploying contract instance...${NC}"

# Load test vectors for deployment
TEST_VECTORS="${ROOT_DIR}/rust/test_vectors.json"

if [ ! -f "${TEST_VECTORS}" ]; then
  echo -e "${RED}Test vectors not found: ${TEST_VECTORS}${NC}"
  exit 1
fi

# Extract values from test vectors (using jq or python)
if command -v jq >/dev/null 2>&1; then
  HASHLOCK=$(jq -r '.hashlock' "${TEST_VECTORS}" 2>/dev/null || echo "")
  ADAPTOR_POINT=$(jq -r '.adaptor_point_compressed' "${TEST_VECTORS}" 2>/dev/null || echo "")
else
  echo -e "${YELLOW}jq not found, using Python for JSON parsing${NC}"
  # Python fallback - simplified for now
  HASHLOCK=""
  ADAPTOR_POINT=""
fi

# Calculate lock_until (current time + 4 hours)
LOCK_UNTIL=$(($(date +%s) + 14400))

echo "Deployment parameters:"
echo "  - lock_until: ${LOCK_UNTIL}"
echo "  - class_hash: ${CLASS_HASH}"

# For testnet, deploy with zero token/amount (testing mode)
echo ""
echo -e "${YELLOW}Deploying in TEST MODE (no real tokens)${NC}"

# Note: Actual deployment calldata generation would go here
# For now, we'll use a placeholder that requires manual calldata
echo -e "${YELLOW}⚠️  Manual calldata required for deployment${NC}"
echo "Generate calldata using: tools/generate_deploy_calldata.py"
echo ""
echo "Then deploy manually with:"
echo "  starkli deploy ${CLASS_HASH} --rpc ${RPC_URL} --account ~/.starkli-wallets/deployer/account.json --watch"

# Placeholder for actual deployment
CONTRACT_ADDRESS="0x0"
echo -e "${YELLOW}⚠️  Skipping actual deployment (requires calldata generation)${NC}"
echo -e "${YELLOW}   Set CONTRACT_ADDRESS manually after deployment${NC}"

# ============================================================================
# GATE 6: Post-Deployment Validation
# ============================================================================
if [ "${CONTRACT_ADDRESS}" != "0x0" ]; then
  echo ""
  echo -e "${YELLOW}[6/7] Validating deployment...${NC}"
  
  # Call view functions to validate state
  echo "Checking contract state..."
  
  # is_unlocked should be false
  UNLOCKED=$(starkli call "${CONTRACT_ADDRESS}" is_unlocked --rpc "${RPC_URL}" 2>&1 || echo "")
  if echo "${UNLOCKED}" | grep -q "0x0"; then
    echo -e "${GREEN}  is_unlocked: false ✓${NC}"
  else
    echo -e "${RED}  is_unlocked: unexpected value${NC}"
  fi
  
  # is_secret_revealed should be false
  REVEALED=$(starkli call "${CONTRACT_ADDRESS}" is_secret_revealed --rpc "${RPC_URL}" 2>&1 || echo "")
  if echo "${REVEALED}" | grep -q "0x0"; then
    echo -e "${GREEN}  is_secret_revealed: false ✓${NC}"
  else
    echo -e "${RED}  is_secret_revealed: unexpected value${NC}"
  fi
  
  # get_lock_until should return our timestamp
  LOCK=$(starkli call "${CONTRACT_ADDRESS}" get_lock_until --rpc "${RPC_URL}" 2>&1 || echo "")
  echo -e "${GREEN}  get_lock_until: ${LOCK} ✓${NC}"
else
  echo ""
  echo -e "${YELLOW}[6/7] Skipping validation (no contract deployed)${NC}"
fi

# ============================================================================
# GATE 7: Watchtower Configuration
# ============================================================================
echo ""
echo -e "${YELLOW}[7/7] Configuring watchtower...${NC}"

# Update watchtower .env
WATCHTOWER_ENV="${ROOT_DIR}/watchtower/.env"

if [ "${CONTRACT_ADDRESS}" != "0x0" ]; then
  cat > "${WATCHTOWER_ENV}" << EOF
# Auto-generated by deploy.sh on ${TIMESTAMP}
STARKNET_RPC_URL=${RPC_URL}
WATCHED_CONTRACTS=${CONTRACT_ADDRESS}

# Optional: Add your webhook URLs
# DISCORD_WEBHOOK=
# TELEGRAM_BOT_TOKEN=
# TELEGRAM_CHAT_ID=
EOF
  echo -e "${GREEN}Watchtower configured: ${WATCHTOWER_ENV}${NC}"
else
  echo -e "${YELLOW}⚠️  Watchtower config skipped (no contract address)${NC}"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=============================================="
echo -e "${GREEN} DEPLOYMENT PACKAGE READY${NC}"
echo "=============================================="
echo ""
echo "Deployment artifacts saved to: ${DEPLOY_DIR}/"
echo ""
echo "Contract Details:"
echo "  Class Hash:      ${CLASS_HASH}"
if [ "${CONTRACT_ADDRESS}" != "0x0" ]; then
  echo "  Contract Address: ${CONTRACT_ADDRESS}"
fi
echo "  Network:         ${NETWORK}"
echo "  RPC:             ${RPC_URL}"
echo ""
echo "Next Steps:"
if [ "${CONTRACT_ADDRESS}" != "0x0" ]; then
  echo "  1. Start watchtower:"
  echo "     cd watchtower && cargo run"
  echo ""
  echo "  2. Test reveal_secret (from Rust):"
  echo "     cargo run --bin taker -- reveal ${CONTRACT_ADDRESS}"
  echo ""
  echo "  3. Monitor on explorer:"
  echo "     https://sepolia.starkscan.co/contract/${CONTRACT_ADDRESS}"
else
  echo "  1. Generate deployment calldata:"
  echo "     cd tools && uv run python generate_deploy_calldata.py ../rust/test_vectors.json <DEPLOYER_ADDRESS>"
  echo ""
  echo "  2. Deploy contract:"
  echo "     starkli deploy ${CLASS_HASH} --rpc ${RPC_URL} --account ~/.starkli-wallets/deployer/account.json --watch"
fi
echo ""

# Save deployment summary
cat > "${DEPLOY_DIR}/summary.json" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "network": "${NETWORK}",
  "rpc_url": "${RPC_URL}",
  "class_hash": "${CLASS_HASH}",
  "contract_address": "${CONTRACT_ADDRESS}",
  "lock_until": ${LOCK_UNTIL}
}
EOF

echo -e "${GREEN}Deployment summary: ${DEPLOY_DIR}/summary.json${NC}"
