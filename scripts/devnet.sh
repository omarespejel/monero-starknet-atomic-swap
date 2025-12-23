#!/bin/bash
# Modern devnet management script for Starknet devnet
# Handles starting, stopping, status checking, and health verification

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEVNET_IMAGE="shardlabs/starknet-devnet-rs"
DEVNET_PORT="5050"
DEVNET_CONTAINER_NAME="starknet-devnet"
DEVNET_URL="http://127.0.0.1:${DEVNET_PORT}"
SEED="${DEVNET_SEED:-0}"  # Use --seed 0 for deterministic accounts

# Account info for --seed 0 (from devnet output)
# First account (Account 0)
DEVNET_ACCOUNT_0="0x049a5a5c30836ff78b3f9a2c0868eaabeeb1ca8ea049d2ed435ad42fd6315fba"
DEVNET_PRIVATE_KEY_0="0x000000000000000000000000000000001e010f076fad70290a3d89c1ec9dd269"
# Second account (Account 1)
DEVNET_ACCOUNT_1="0x02af4cdbeb67c938c5fcdb354c5708e7d7c87e6acc868859a011bcb38473fb9e"
DEVNET_PRIVATE_KEY_1="0x00000000000000000000000000000000e132b5e8842126aa80a5943611177a1c"
# Legacy variables (use Account 0)
DEVNET_ACCOUNT="${DEVNET_ACCOUNT_0}"
DEVNET_PRIVATE_KEY="${DEVNET_PRIVATE_KEY_0}"

# Functions
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi
}

is_devnet_running() {
    docker ps --filter "name=${DEVNET_CONTAINER_NAME}" --filter "status=running" --format "{{.Names}}" | grep -q "^${DEVNET_CONTAINER_NAME}$"
}

wait_for_devnet() {
    local max_attempts=30
    local attempt=0
    
    print_info "Waiting for devnet to be ready..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -f "${DEVNET_URL}/is_alive" > /dev/null 2>&1; then
            print_success "Devnet is ready!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 1
    done
    
    echo ""
    print_error "Devnet failed to start within ${max_attempts} seconds"
    return 1
}

check_devnet_health() {
    if ! is_devnet_running; then
        print_error "Devnet is not running"
        return 1
    fi
    
    if curl -s -f "${DEVNET_URL}/is_alive" > /dev/null 2>&1; then
        print_success "Devnet is healthy"
        
        # Try to get block info
        local block_info=$(curl -s -X POST "${DEVNET_URL}/rpc" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"starknet_getBlockWithTxHashes","params":{"block_id":"latest"}}' 2>/dev/null)
        
        if [ $? -eq 0 ] && echo "$block_info" | grep -q "block_number"; then
            local block_num=$(echo "$block_info" | grep -o '"block_number":[0-9]*' | grep -o '[0-9]*' | head -1)
            print_info "Latest block: ${block_num}"
        fi
        
        return 0
    else
        print_error "Devnet is running but not responding"
        return 1
    fi
}

start_devnet() {
    print_header "Starting Starknet Devnet"
    
    check_docker
    
    if is_devnet_running; then
        print_warning "Devnet is already running"
        check_devnet_health
        return 0
    fi
    
    # Remove old container if it exists
    if docker ps -a --filter "name=${DEVNET_CONTAINER_NAME}" --format "{{.Names}}" | grep -q "^${DEVNET_CONTAINER_NAME}$"; then
        print_info "Removing old devnet container..."
        docker rm -f "${DEVNET_CONTAINER_NAME}" > /dev/null 2>&1 || true
    fi
    
    print_info "Starting devnet container..."
    print_info "  Image: ${DEVNET_IMAGE}"
    print_info "  Port: ${DEVNET_PORT}"
    print_info "  Seed: ${SEED} (deterministic accounts)"
    print_info "  Container: ${DEVNET_CONTAINER_NAME}"
    echo ""
    
    docker run -d \
        --name "${DEVNET_CONTAINER_NAME}" \
        -p "${DEVNET_PORT}:5050" \
        "${DEVNET_IMAGE}" \
        --seed "${SEED}" \
        --port 5050 \
        > /dev/null
    
    if [ $? -eq 0 ]; then
        print_success "Devnet container started"
        wait_for_devnet
        
        echo ""
        print_info "Pre-funded accounts (seed ${SEED}):"
        echo "  Account 0:"
        echo "    Address: ${DEVNET_ACCOUNT_0}"
        echo "    Private Key: ${DEVNET_PRIVATE_KEY_0}"
        echo "  Account 1:"
        echo "    Address: ${DEVNET_ACCOUNT_1}"
        echo "    Private Key: ${DEVNET_PRIVATE_KEY_1}"
        echo ""
        print_info "Initial Balance: 1000000000000000000000 WEI and FRI per account"
        echo ""
        print_info "RPC URL: ${DEVNET_URL}"
        print_info "View logs: docker logs -f ${DEVNET_CONTAINER_NAME}"
    else
        print_error "Failed to start devnet container"
        exit 1
    fi
}

stop_devnet() {
    print_header "Stopping Starknet Devnet"
    
    if ! is_devnet_running; then
        print_warning "Devnet is not running"
        return 0
    fi
    
    print_info "Stopping devnet container..."
    docker stop "${DEVNET_CONTAINER_NAME}" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "Devnet stopped"
    else
        print_error "Failed to stop devnet"
        exit 1
    fi
}

restart_devnet() {
    print_header "Restarting Starknet Devnet"
    stop_devnet
    sleep 2
    start_devnet
}

status_devnet() {
    print_header "Devnet Status"
    
    if is_devnet_running; then
        print_success "Container is running"
        check_devnet_health
        
        echo ""
        print_info "Container details:"
        docker ps --filter "name=${DEVNET_CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        
        echo ""
        print_info "Recent logs (last 10 lines):"
        docker logs --tail 10 "${DEVNET_CONTAINER_NAME}" 2>&1 | sed 's/^/  /'
    else
        print_error "Devnet is not running"
        echo ""
        print_info "Start it with: $0 start"
    fi
}

logs_devnet() {
    if ! is_devnet_running; then
        print_error "Devnet is not running"
        exit 1
    fi
    
    print_info "Following devnet logs (Ctrl+C to exit)..."
    docker logs -f "${DEVNET_CONTAINER_NAME}"
}

test_devnet() {
    print_header "Testing Devnet Connection"
    
    if ! is_devnet_running; then
        print_error "Devnet is not running. Start it first with: $0 start"
        exit 1
    fi
    
    print_info "Running connection test..."
    
    if cargo test --manifest-path rust/Cargo.toml --test devnet_e2e_test test_devnet_connection -- --ignored --nocapture 2>&1 | tail -20; then
        print_success "Devnet connection test passed"
    else
        print_error "Devnet connection test failed"
        exit 1
    fi
}

show_help() {
    cat << EOF
${BLUE}Starknet Devnet Management Script${NC}

Usage: $0 [COMMAND]

Commands:
  start       Start devnet container (with --seed 0 for deterministic accounts)
  stop        Stop devnet container
  restart     Restart devnet container
  status      Show devnet status and health
  logs        Follow devnet logs (Ctrl+C to exit)
  test        Run devnet connection test
  help        Show this help message

Environment Variables:
  DEVNET_SEED         Seed for deterministic accounts (default: 0)
                      Use 0 for pre-funded accounts

Examples:
  $0 start              # Start devnet with seed 0
  $0 status             # Check if devnet is running
  $0 test               # Run connection test
  DEVNET_SEED=1 $0 start # Start with different seed

Account Info (seed 0):
  Account 0:
    Address: ${DEVNET_ACCOUNT_0}
    Private Key: ${DEVNET_PRIVATE_KEY_0}
  Account 1:
    Address: ${DEVNET_ACCOUNT_1}
    Private Key: ${DEVNET_PRIVATE_KEY_1}
  
  Initial Balance: 1000000000000000000000 WEI and FRI per account

EOF
}

# Main command dispatcher
case "${1:-help}" in
    start)
        start_devnet
        ;;
    stop)
        stop_devnet
        ;;
    restart)
        restart_devnet
        ;;
    status)
        status_devnet
        ;;
    logs)
        logs_devnet
        ;;
    test)
        test_devnet
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac

