.PHONY: format format-rust format-python format-cairo check-format help context context-monero context-cairo test test-rust test-cairo test-security test-e2e lint fmt clean

help:
	@echo "Code formatting commands:"
	@echo "  make format          - Format all code (Rust, Python, Cairo)"
	@echo "  make format-rust     - Format Rust code"
	@echo "  make format-python   - Format Python code"
	@echo "  make format-cairo    - Format Cairo code"
	@echo "  make check-format    - Check formatting without modifying files"
	@echo ""
	@echo "Testing commands:"
	@echo "  make test            - Run all tests (Rust + Cairo)"
	@echo "  make test-rust       - Run Rust tests"
	@echo "  make test-cairo      - Run Cairo tests"
	@echo "  make test-security   - Run security tests (CRITICAL)"
	@echo "  make test-e2e        - Run end-to-end tests"
	@echo ""
	@echo "Context generation commands:"
	@echo "  make context         - Generate full project context"
	@echo "  make context-monero  - Generate Monero-focused context"
	@echo "  make context-cairo   - Generate Cairo-focused context"
	@echo ""
	@echo "Linting commands:"
	@echo "  make lint            - Run linters (clippy, fmt check)"
	@echo "  make fmt             - Format all code"
	@echo ""
	@echo "Cleanup commands:"
	@echo "  make clean           - Remove generated files and build artifacts"

format: format-rust format-python format-cairo

format-rust:
	@echo "Formatting Rust code..."
	cd rust && cargo fmt

format-python:
	@echo "Formatting Python code..."
	black --line-length=100 tools/ rust/tests/ || ruff format tools/ rust/tests/

format-cairo:
	@echo "Formatting Cairo code..."
	cd cairo && scarb fmt

check-format:
	@echo "Checking code formatting..."
	cd rust && cargo fmt --all -- --check
	black --check --line-length=100 tools/ rust/tests/ || ruff format --check tools/ rust/tests/
	cd cairo && scarb fmt --check || true

context:
	@echo "Generating full project context..."
	repomix --config repomix.config.json
	@echo "✅ Context written to context-full.xml"

context-monero:
	@echo "Generating Monero-focused context..."
	repomix --config repomix.monero.json
	@echo "✅ Context written to context-monero.xml"

context-cairo:
	@echo "Generating Cairo-focused context..."
	repomix --config repomix.cairo.json
	@echo "✅ Context written to context-cairo.xml"

# Testing
test: test-rust test-cairo

test-rust:
	@echo "Running Rust tests..."
	cd rust && cargo test --workspace

test-cairo:
	@echo "Running Cairo tests..."
	cd cairo && snforge test

test-security:
	@echo "Running security tests (CRITICAL)..."
	cd cairo && snforge test security -v

test-e2e:
	@echo "Running end-to-end tests..."
	cd cairo && snforge test e2e -v

# Linting
lint:
	@echo "Running linters..."
	cd rust && cargo clippy --workspace -- -D warnings
	cd rust && cargo fmt --all -- --check
	cd cairo && scarb fmt --check || true

fmt: format

# Cleanup
clean:
	@echo "Cleaning generated files..."
	rm -f context*.xml
	rm -f monero-swap-context-*.txt
	rm -f xmr-starknet-swap-context-*.txt
	cd rust && cargo clean
	cd cairo && scarb clean

