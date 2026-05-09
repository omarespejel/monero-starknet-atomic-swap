#!/usr/bin/env python3
"""Legacy hint-scalar verifier."""

raise SystemExit(
    "verify_hint_scalars.py is disabled because it targets stale scalar handling. "
    "Use `uv run --project tools python tools/regenerate_dleq_hints.py` and inspect "
    "cairo/generated_dleq_vectors.json."
)
