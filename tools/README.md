# Monero Test Data Generator (Python + uv)

Python tooling to generate Ed25519 test vectors for the Cairo AtomicLock MSM check.

## Setup (uv)

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create venv and install deps
cd tools
uv venv
source .venv/bin/activate  # on Windows: .venv\Scripts\activate
uv pip install -e ".[dev]"
```

## Usage

```bash
# Generate with default scalar
uv run python generate_ed25519_test_data.py

# Generate with custom scalar (hex)
uv run python generate_ed25519_test_data.py a1b2c3...

# Save to JSON
uv run python generate_ed25519_test_data.py --save
```

## Output
- Secret scalar (hex and Cairo u256 literal)
- Adaptor point T = t·G in Weierstrass u384 limbs (4 × 96-bit) and Cairo tuple form
- Fake-GLV hint (Cairo array of felts)
- Copy-paste snippet for Cairo tests

Use the printed `x_limbs`, `y_limbs`, and `hint` in `deploy_with_full` in `cairo/tests/test_atomic_lock.cairo`, then remove MSM zero-guards to enforce `t·G == adaptor_point`.***

