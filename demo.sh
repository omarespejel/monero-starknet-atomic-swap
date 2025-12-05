#!/bin/bash
# End-to-end atomic swap demo script
#
# This script demonstrates the full swap flow:
# 1. Maker generates secret and prepares swap
# 2. Taker watches for contract and unlocks
# 3. Maker finalizes Monero signature
#
# Usage:
#   ./demo.sh maker   # Run maker side
#   ./demo.sh taker  # Run taker side

set -e

ROLE=${1:-maker}
RUST_DIR="rust"
STARKNET_RPC="https://starknet-sepolia.public.blastapi.io/rpc/v0_7"
MONERO_RPC="http://stagenet.community.rino.io:38081"

cd "$(dirname "$0")"

case "$ROLE" in
    maker)
        echo "🔐 Running Maker (Alice) side..."
        echo ""
        echo "This will:"
        echo "  1. Generate secret scalar t"
        echo "  2. Create adaptor signature for Monero"
        echo "  3. Prepare contract deployment data"
        echo "  4. Save swap state to swap_state.json"
        echo ""
        read -p "Press Enter to continue..."
        
        cargo run --manifest-path "$RUST_DIR/Cargo.toml" --bin maker -- \
            --starknet-rpc "$STARKNET_RPC" \
            --monero-rpc "$MONERO_RPC" \
            --lock-duration 3600 \
            --output swap_state.json
        
        echo ""
        echo "✅ Maker setup complete!"
        echo "   Next steps:"
        echo "   1. Deploy contract using swap_state.json"
        echo "   2. Share adaptor signature/terms with taker"
        echo "   3. Run: ./demo.sh maker-watch <contract_address>"
        ;;
    
    maker-watch)
        CONTRACT_ADDR=${2:-""}
        if [ -z "$CONTRACT_ADDR" ]; then
            echo "❌ Error: Contract address required"
            echo "Usage: ./demo.sh maker-watch <contract_address>"
            exit 1
        fi
        
        echo "👀 Watching for unlock event..."
        echo "   Contract: $CONTRACT_ADDR"
        echo ""
        echo "⚠️  Event watching requires full starknet-rs integration"
        echo "   For now, monitor manually or implement event watcher"
        ;;
    
    taker)
        echo "🔓 Running Taker (Bob) side..."
        echo ""
        echo "Options:"
        echo "  1. Watch mode: Monitor for new contracts"
        echo "  2. Unlock mode: Unlock a specific contract"
        echo ""
        read -p "Enter mode (watch/unlock): " MODE
        
        case "$MODE" in
            watch)
                echo ""
                echo "👀 Watching for AtomicLock contracts..."
                cargo run --manifest-path "$RUST_DIR/Cargo.toml" --bin taker -- \
                    --starknet-rpc "$STARKNET_RPC" \
                    --watch
                ;;
            unlock)
                read -p "Contract address: " CONTRACT_ADDR
                read -p "Secret (hex): " SECRET
                
                echo ""
                echo "🔓 Unlocking contract..."
                cargo run --manifest-path "$RUST_DIR/Cargo.toml" --bin taker -- \
                    --starknet-rpc "$STARKNET_RPC" \
                    --contract-address "$CONTRACT_ADDR" \
                    --secret "$SECRET"
                ;;
            *)
                echo "❌ Invalid mode: $MODE"
                exit 1
                ;;
        esac
        ;;
    
    *)
        echo "Usage: $0 {maker|maker-watch|taker}"
        echo ""
        echo "Commands:"
        echo "  maker         - Run maker side (generate secret, prepare swap)"
        echo "  maker-watch   - Watch for unlock event (requires contract address)"
        echo "  taker         - Run taker side (watch or unlock)"
        exit 1
        ;;
esac

