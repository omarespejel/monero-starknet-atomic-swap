#!/bin/bash
set -euo pipefail

echo "🔧 Setting up AI development environment..."

# 1. Install repomix
if ! command -v repomix &> /dev/null; then
    echo "📦 Installing repomix..."
    npm install -g repomix
fi

# 2. Create directories
mkdir -p .cursor/rules

# 3. Verify .cursorrules exists
if [ ! -f .cursorrules ]; then
    echo "⚠️  Warning: .cursorrules not found. Please create it manually."
fi

# 4. Verify MCP config exists
if [ ! -f .cursor/mcp.json ]; then
    echo "⚠️  Warning: .cursor/mcp.json not found. Please create it manually."
fi

# 5. Verify CLAUDE.md exists
if [ ! -f CLAUDE.md ]; then
    echo "⚠️  Warning: CLAUDE.md not found. Please create it manually."
fi

# 6. Add context files to .gitignore
if ! grep -q "context*.xml" .gitignore 2>/dev/null; then
    echo "" >> .gitignore
    echo "# AI context files (regenerate with repomix)" >> .gitignore
    echo "context*.xml" >> .gitignore
fi

echo "✅ AI tools configured!"
echo ""
echo "Usage:"
echo "  repomix                              # Full context"
echo "  repomix --config repomix.monero.json # Monero only"
echo "  repomix --config repomix.cairo.json  # Cairo only"
echo ""
echo "Note: generate-context.sh is preserved as requested"

