# Monero/Starknet DLEQ Tooling (Python + uv)

Python tooling for regenerating Cairo DLEQ vectors, Garaga sqrt hints, and deployment calldata.

The canonical DLEQ generator is `regenerate_dleq_hints.py`. It uses the full Poseidon challenge felt
and full Ed25519 response scalar. Older hint scripts that truncated values to 128 bits, used BLAKE2s
transcripts, or emitted placeholder hints are guarded and must not be used for production data.

The DLEQ second generator is derived in Rust by `dleq::get_second_generator()` from a
domain-separated transcript. If that derivation changes, regenerate `rust/test_vectors.json` first,
then run this tool and update the hardcoded Cairo second-generator constants together.

## Setup (uv)

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# From the repo root, install the tools project deps
uv sync --project tools
```

## Usage

```bash
# Regenerate the Rust vector first when the DLEQ generator/proof code changes
cd rust
cargo test -q --test test_vectors generate_cairo_test_vectors -- --ignored --nocapture
cd ..

# Regenerate Cairo DLEQ vectors and hints from rust/test_vectors.json
uv run --project tools python tools/regenerate_dleq_hints.py

# Generate constructor calldata after DLEQ vectors are current
python3 tools/generate_deploy_calldata.py \
  --network sepolia \
  --token 0x... \
  --amount 1000000000000000000 \
  --lock-until 1893456000

# Zero-amount constructor calldata is only for local/test deployments
python3 tools/generate_deploy_calldata.py --allow-zero-lock --lock-until 1893456000
```

## Output

- `cairo/generated_dleq_vectors.json`
- `cairo/test_hints.json`
- `cairo/adaptor_point_hint.json`
- `deployments/<network>/latest_calldata.txt`
