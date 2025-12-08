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
	@DATE=$$(date '+%Y-%m-%d_%H-%M-%S_%Z'); \
	OUTPUT_FILE="context-full-$${DATE}.xml"; \
	cp repomix.config.json repomix.config.json.bak && \
	jq ".output.filePath = \"$$OUTPUT_FILE\"" repomix.config.json > repomix.config.json.tmp && \
	mv repomix.config.json.tmp repomix.config.json && \
	(repomix --config repomix.config.json || (mv repomix.config.json.bak repomix.config.json && exit 1)) && \
	jq ".output.filePath = \"context-full.xml\"" repomix.config.json > repomix.config.json.tmp && \
	mv repomix.config.json.tmp repomix.config.json && \
	rm -f repomix.config.json.bak && \
	echo "✅ Context written to $$OUTPUT_FILE"

context-monero:
	@echo "Generating Monero-focused context..."
	@DATE=$$(date '+%Y-%m-%d_%H-%M-%S_%Z'); \
	OUTPUT_FILE="context-monero-$${DATE}.xml"; \
	cp repomix.monero.json repomix.monero.json.bak && \
	jq ".output.filePath = \"$$OUTPUT_FILE\"" repomix.monero.json > repomix.monero.json.tmp && \
	mv repomix.monero.json.tmp repomix.monero.json && \
	(repomix --config repomix.monero.json || (mv repomix.monero.json.bak repomix.monero.json && exit 1)) && \
	jq ".output.filePath = \"context-monero.xml\"" repomix.monero.json > repomix.monero.json.tmp && \
	mv repomix.monero.json.tmp repomix.monero.json && \
	rm -f repomix.monero.json.bak && \
	echo "✅ Context written to $$OUTPUT_FILE"

context-cairo:
	@echo "Generating Cairo-focused context..."
	@DATE=$$(date '+%Y-%m-%d_%H-%M-%S_%Z'); \
	OUTPUT_FILE="context-cairo-$${DATE}.xml"; \
	cp repomix.cairo.json repomix.cairo.json.bak && \
	jq ".output.filePath = \"$$OUTPUT_FILE\"" repomix.cairo.json > repomix.cairo.json.tmp && \
	mv repomix.cairo.json.tmp repomix.cairo.json && \
	(repomix --config repomix.cairo.json || (mv repomix.cairo.json.bak repomix.cairo.json && exit 1)) && \
	jq ".output.filePath = \"context-cairo.xml\"" repomix.cairo.json > repomix.cairo.json.tmp && \
	mv repomix.cairo.json.tmp repomix.cairo.json && \
	rm -f repomix.cairo.json.bak && \
	echo "✅ Context written to $$OUTPUT_FILE"

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
	rm -f context-*-*.xml
	rm -f monero-swap-context-*.txt
	rm -f xmr-starknet-swap-context-*.txt
	rm -f repomix.*.json.bak
	rm -f repomix.*.json.tmp
	cd rust && cargo clean
	cd cairo && scarb clean

