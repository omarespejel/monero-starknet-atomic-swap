.PHONY: format format-rust format-python format-cairo check-format help

help:
	@echo "Code formatting commands:"
	@echo "  make format          - Format all code (Rust, Python, Cairo)"
	@echo "  make format-rust     - Format Rust code"
	@echo "  make format-python   - Format Python code"
	@echo "  make format-cairo    - Format Cairo code"
	@echo "  make check-format    - Check formatting without modifying files"

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

