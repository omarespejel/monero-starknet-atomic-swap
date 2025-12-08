# Context Generation Guide

This document explains how to generate LLM-friendly context files for the Monero-Starknet atomic swap project.

## Quick Start

### Using Repomix (Recommended)

```bash
# Full project context
make context
# Output: context-full.xml

# Monero-focused context (Rust key splitting + DLEQ)
make context-monero
# Output: context-monero.xml

# Cairo-focused context (contracts + tests)
make context-cairo
# Output: context-cairo.xml
```

Or directly:
```bash
repomix --config repomix.config.json
repomix --config repomix.monero.json
repomix --config repomix.cairo.json
```

### Using generate-context.sh (Legacy)

```bash
./generate-context.sh
# Output: monero-swap-context-YYYY-MM-DD_HH-MM-SS_TZ.txt
```

## Comparison: Repomix vs generate-context.sh

| Feature | Repomix | generate-context.sh |
|---------|---------|---------------------|
| **Format** | XML (structured) | Plain text (unstructured) |
| **Size** | Smaller (focused) | Larger (comprehensive) |
| **Speed** | Fast (~5-10s) | Slower (~30-60s) |
| **Customization** | JSON config files | Bash script (754 lines) |
| **Maintenance** | Low (config-driven) | High (manual script updates) |
| **AI Compatibility** | Excellent (structured XML) | Good (plain text) |
| **Selective Context** | ✅ Yes (3 profiles) | ❌ No (all-or-nothing) |
| **Historical Context** | ❌ No | ✅ Yes (debugging history) |
| **File Count** | ~104 files (comprehensive) | ~100+ files |

## Repomix Configuration Profiles

### 1. Full Context (`repomix.config.json`)

**Purpose**: Complete project overview for comprehensive understanding

**Includes**:
- All core Rust code (key splitting, DLEQ, adaptor, binaries)
- All Cairo contracts and ALL tests (security, E2E, integration, unit, debug)
- All documentation (README, SECURITY.md, ARCHITECTURE.md, PROTOCOL.md, ADRs)
- Key Python tools (hint generation, verification, conversion)
- Test fixtures and helpers
- Test vectors and hint files
- Comprehensive coverage matching generate-context.sh

**Use Case**: Complete project understanding, comprehensive audits, deep debugging

**Output**: `context-full.xml` (~800KB-1.5MB, ~242k tokens, ~104 files)

### 2. Monero Context (`repomix.monero.json`)

**Purpose**: Focused on Rust cryptography and key splitting

**Includes**:
- All Rust cryptography code (key splitting, DLEQ, adaptor, starknet)
- All Rust tests (integration, E2E, properties, test vectors)
- Key Rust binaries (maker, taker, generate_test_vector)
- Rust documentation (AUDIT_DEPENDENCIES.md)
- Test vectors JSON
- Key splitting security analysis
- Race condition mitigation docs
- Related ADRs (key splitting decision)
- Cross-platform verification tools
- Excludes: Cairo code, Python tools, debug files

**Use Case**: Rust cryptography work, key splitting analysis, DLEQ proof generation

**Output**: `context-monero.xml` (~250KB, ~72k tokens, ~37 files)

### 3. Cairo Context (`repomix.cairo.json`)

**Purpose**: Focused on Cairo contracts and verification

**Includes**:
- All Cairo contracts (AtomicLock, BLAKE2s, serialization)
- ALL Cairo tests (security, E2E, integration, unit, debug)
- Test fixtures and helpers
- Cairo configuration files (Scarb.toml, snfoundry.toml, coverage.toml)
- Cairo documentation (INVARIANTS.md, README_TESTS.md)
- Test hint files (JSON)
- Key Python tools for hint generation and verification
- Related documentation (PROTOCOL.md, ARCHITECTURE.md sections, ADRs)
- Excludes: Rust code, most Python tools, build artifacts

**Use Case**: Cairo contract development, security audits, comprehensive testing

**Output**: `context-cairo.xml` (~490KB, ~150k tokens, ~58 files)

## generate-context.sh Features

### Advantages

1. **Historical Context**: Includes extensive debugging history and fix documentation
2. **Comprehensive**: Includes ALL files (tests, tools, binaries, debug files)
3. **Self-Documenting**: Contains project status, recent fixes, known issues
4. **Test Coverage**: Includes all test files (107 Cairo tests, 32 Rust tests)

### Disadvantages

1. **Large Size**: ~2-5MB text files (harder for LLMs to process)
2. **Slow**: Takes 30-60 seconds to generate
3. **Maintenance**: Requires manual script updates (754 lines)
4. **No Filtering**: All-or-nothing approach

### When to Use

- **Deep debugging**: Need historical context and fix documentation
- **Complete audit**: Need every file including debug tests
- **Legacy workflows**: Existing scripts/tools depend on it
- **Documentation**: Want self-contained project history

## Repomix Advantages

### Advantages

1. **Structured Format**: XML format is easier for LLMs to parse
2. **Fast**: Generates in seconds
3. **Configurable**: Easy to adjust what's included
4. **Selective**: Three profiles for different use cases
5. **Modern**: Industry-standard tool (used by many projects)
6. **Maintainable**: JSON config is easier to update

### Disadvantages

1. **No History**: Doesn't include debugging history (but includes all current files)
2. **Less Historical Context**: No embedded fix documentation (but includes all code)
3. **Learning Curve**: Need to understand JSON config format

### When to Use

- **Daily Development**: Quick context for focused work
- **AI Assistance**: Better structured format for LLMs
- **Selective Context**: Need only specific parts of codebase
- **Modern Workflows**: Using Cursor IDE or other modern tools

## Recommendations

### For Daily Development

**Use Repomix** with focused profiles:
```bash
# Working on Rust cryptography
make context-monero

# Working on Cairo contracts
make context-cairo

# Full project review
make context
```

### For Deep Debugging

**Use generate-context.sh** when you need:
- Historical debugging context
- All test files including debug tests
- Complete project history
- Self-contained documentation

### For AI Assistance (Cursor IDE)

**Use Repomix** - The structured XML format works better with:
- Cursor's MCP servers
- Modern AI tools
- Selective context loading

## File Locations

### Repomix Outputs

- `context-full.xml` - Full project context
- `context-monero.xml` - Monero-focused context
- `context-cairo.xml` - Cairo-focused context

### generate-context.sh Output

- `monero-swap-context-YYYY-MM-DD_HH-MM-SS_TZ.txt` - Timestamped context files

## Updating Configurations

### Adding Files to Repomix

Edit the appropriate config file (`repomix.*.json`):

```json
{
  "include": [
    "path/to/new/file.rs",
    "path/to/directory/**"
  ],
  "ignore": {
    "customPatterns": [
      "path/to/exclude/**"
    ]
  }
}
```

### Updating generate-context.sh

Edit the bash script arrays:
- `CAIRO_TESTS_SECURITY`
- `RUST_SOURCE`
- `TOOLS_PYTHON`
- etc.

## Best Practices

1. **Use Repomix for daily work** - Faster, more focused
2. **Use generate-context.sh for audits** - More comprehensive
3. **Keep both updated** - Different use cases
4. **Commit configs** - Version control your context generation
5. **Document changes** - Update this guide when adding new files

## Example Workflows

### Starting a New Feature

```bash
# 1. Generate focused context
make context-monero  # or context-cairo

# 2. Load in Cursor IDE
# Context is automatically available via MCP

# 3. Work on feature
# AI has focused context, faster responses
```

### Preparing for Audit

```bash
# 1. Generate comprehensive context
./generate-context.sh

# 2. Share with auditor
# Contains all files + historical context

# 3. Auditor has complete picture
# Including debugging history and fixes
```

### Debugging an Issue

```bash
# 1. Generate full context (includes debug tests)
./generate-context.sh

# 2. Review historical fixes
# Script includes extensive debugging history

# 3. Find similar past issues
# Historical context helps identify patterns
```

---

**Version**: 0.7.1-alpha  
**Last Updated**: 2025-12-07

