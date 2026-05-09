#!/usr/bin/env python3
"""Legacy DLEQ hint fixer.

This entry point used the old 128-bit-truncated scalar path and is intentionally
disabled. Regenerate production/test vectors with:

    uv run --project tools python tools/regenerate_dleq_hints.py
"""

raise SystemExit(
    "fix_all_hints.py is disabled because it targets the legacy truncated DLEQ path. "
    "Use `uv run --project tools python tools/regenerate_dleq_hints.py` instead."
)
