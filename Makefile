.PHONY: format format-rust format-python format-cairo check-format help context context-monero context-cairo

help:
	@echo "Code formatting commands:"
	@echo "  make format          - Format all code (Rust, Python, Cairo)"
	@echo "  make format-rust     - Format Rust code"
	@echo "  make format-python   - Format Python code"
	@echo "  make format-cairo    - Format Cairo code"
	@echo "  make check-format    - Check formatting without modifying files"
	@echo ""
	@echo "Context generation commands:"
	@echo "  make context         - Generate full project context (context-full.xml)"
	@echo "  make context-monero  - Generate Monero-focused context (context-monero.xml)"
	@echo "  make context-cairo   - Generate Cairo-focused context (context-cairo.xml)"

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

