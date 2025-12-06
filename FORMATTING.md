# Code Formatting Guide

This repository uses automated code formatting tools to maintain consistent style across Cairo, Rust, and Python code.

## Quick Start

Format all code:
```bash
make format
```

Format individual languages:
```bash
make format-rust      # Format Rust code
make format-python    # Format Python code
make format-cairo     # Format Cairo code
```

Check formatting without modifying files:
```bash
make check-format
```

## Language-Specific Tools

### Rust

**Tool**: `rustfmt` (official Rust formatter)

**Configuration**: `.rustfmt.toml`

**Usage**:
```bash
cd rust
cargo fmt                    # Format all Rust code
cargo fmt --all -- --check  # Check formatting without modifying
```

**Features**:
- Line length: 100 characters
- Follows Rust community standards
- Automatic import grouping

### Python

**Tool**: `Black` (opinionated Python formatter)

**Configuration**: `pyproject.toml`

**Usage**:
```bash
black --line-length=100 tools/ rust/tests/  # Format Python code
black --check --line-length=100 tools/ rust/tests/  # Check formatting
```

**Alternative**: `Ruff` (faster, Rust-based)
```bash
ruff format tools/ rust/tests/
ruff format --check tools/ rust/tests/
```

**Features**:
- Line length: 100 characters
- Target Python 3.11+
- PEP 8 compliant

### Cairo

**Tool**: `scarb fmt` (Scarb formatter)

**Usage**:
```bash
cd cairo
scarb fmt           # Format Cairo code
scarb fmt --check   # Check formatting
```

**Note**: Cairo formatter is still evolving. Some formatting may not be perfect.

## Pre-commit Hooks

Install pre-commit hooks to automatically format code before commits:

```bash
pip install pre-commit
pre-commit install
```

This will automatically format Rust and Python code before each commit.

## CI/CD Integration

The `.github/workflows/format-check.yml` workflow automatically checks formatting on:
- Push to `main` branch
- Pull requests to `main` branch

All formatting checks must pass before merging.

## Best Practices

1. **Run formatting before committing**: Use `make format` or pre-commit hooks
2. **Check formatting in CI**: The format-check workflow ensures consistency
3. **Use consistent line length**: 100 characters for all languages
4. **Follow language conventions**: Each formatter enforces language-specific best practices

## Configuration Files

- `.rustfmt.toml` - Rust formatting configuration
- `pyproject.toml` - Python formatting configuration (Black/Ruff)
- `.pre-commit-config.yaml` - Pre-commit hooks configuration
- `Makefile` - Convenience commands for formatting

## References

- [Rustfmt Documentation](https://github.com/rust-lang/rustfmt)
- [Black Documentation](https://black.readthedocs.io/)
- [Ruff Documentation](https://docs.astral.sh/ruff/)
- [Scarb Documentation](https://docs.swmansion.com/scarb/)

