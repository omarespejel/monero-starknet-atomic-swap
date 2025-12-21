#!/bin/bash
# Quick start script - wrapper around devnet.sh
# Usage: ./scripts/start-devnet.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/devnet.sh" start

