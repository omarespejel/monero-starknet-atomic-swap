#!/usr/bin/env python3
"""Legacy arbitrary-adaptor DLEQ generator.

This script previously used the old BLAKE2s challenge path and placeholder sqrt
hints. It must not be used for deploy or test-vector data.
"""

raise SystemExit(
    "generate_dleq_for_adaptor_point.py is disabled because it can emit stale or "
    "placeholder DLEQ data. Use the Rust vector generator plus "
    "`uv run --project tools python tools/regenerate_dleq_hints.py`."
)
