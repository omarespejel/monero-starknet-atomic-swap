# Context Generation for LLMs

This project supports **two approaches** for generating LLM-friendly context:

## Option 1: Repomix (Modern, Recommended)

Repomix is the standard tool for packing codebases for LLMs in 2024/2025.

### Installation

```bash
npm install -g repomix
```

### Usage

```bash
# Generate context with default config
repomix

# Generate Monero-focused context
repomix --include "rust/src/monero/**,rust/src/dleq.rs" -o context-monero.xml

# Generate Cairo-focused context
repomix --include "cairo/src/**,cairo/tests/test_e2e_*" -o context-cairo.xml
```

### Configuration

See `repomix.config.json` for ignore patterns and include lists.

**Output**: `context.xml` (structured XML format with token counting)

**Benefits**:
- Automatic token counting
- Smart file filtering
- Structured XML output
- MCP server integration for Cursor

## Option 2: generate-context.sh (Legacy, Still Supported)

The original bash script approach for comprehensive context generation.

### Usage

```bash
./generate-context.sh
```

**Output**: `monero-swap-context-YYYY-MM-DD_HH-MM-SS_TZ.txt` (plain text format)

**Benefits**:
- Comprehensive file inclusion
- Detailed progress tracking
- Custom formatting
- Works without Node.js

## When to Use Which

| Use Case | Tool |
|----------|------|
| Quick context for specific features | **Repomix** (faster, filtered) |
| Full project context for audit | **generate-context.sh** (comprehensive) |
| Cursor IDE integration | **Repomix** (MCP support) |
| CI/CD context generation | **generate-context.sh** (no dependencies) |

## Cursor Integration

For Cursor IDE, use:
- `@codebase` - Automatic context from repo
- `@Docs` - Add documentation as indexed context
- `.cursorrules` - Project-specific instructions (already configured)

## Best Practices

1. **Selective Context**: Only include what's needed (Repomix default)
2. **Token Awareness**: Check token counts before sending to LLM
3. **Structured Format**: Use XML for better parsing (Repomix)
4. **Version Control**: Don't commit generated context files

