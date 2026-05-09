# Secret Rotation Runbook

This runbook covers accidental Starknet RPC provider-token exposure in tracked
files or reachable git history. It does not replace external secret scanning,
but it gives operators a deterministic local check before pushing, handing off,
or deploying.

## Current-Tree Gate

Run from the repository root:

```bash
python3 tools/check_secret_hygiene.py
```

Expected clean-tree result:

```text
Secret hygiene check passed
```

This is the CI gate. It rejects tracked provider URLs with embedded API keys,
tracked local secret filenames, and literal non-devnet private-key assignments.

## Historical Exposure Scan

Run:

```bash
python3 tools/check_secret_hygiene.py --history --report-only
```

The history mode exits zero with `--report-only` so the output can be attached
to an incident or audit note. It prints only commit/path/line locations and the
finding type; it does not print secret values.

Current local result: the current tree passes, but reachable history still has
historical token-bearing Starknet RPC provider URL locations. Treat those
provider tokens as exposed.

The current history mode is intentionally scoped to provider-token URLs and
sensitive local filenames. The current-tree gate remains responsible for
blocking literal private-key assignments.

## Rotation Steps

1. Revoke or rotate every Starknet RPC provider token that appears in historical
   locations from the history scan.
2. Replace local-only endpoints in shell profiles, `.env` files, the Monero VM,
   and any deployment host config. Do not commit the new endpoint.
3. Rerun:

```bash
python3 tools/check_secret_hygiene.py
python3 tools/check_secret_hygiene.py --history --report-only
```

4. Confirm current-tree output is clean and save the historical report as
   evidence that old values were identified and rotated.
5. If this branch is pushed to a public remote before rotation, assume the token
   was compromised even if the current tree is clean.

## Current Rotation Record

As of `2026-05-09T17:09:12Z`, the operator reported the historical Alchemy
Starknet Sepolia provider key revoked. The current tracked tree passes
`python3 tools/check_secret_hygiene.py`. The historical report still lists
redacted old Alchemy URL locations, which is expected after revocation and
should be retained as incident evidence.

## History Rewrite Policy

Do not rewrite public history casually. If the exposed key has already been
pushed, rotation is the required security fix. History rewriting can reduce
accidental rediscovery, but it does not make the old token safe and can disrupt
reviewers or operators.

If history is still local-only and you decide to rewrite before publication,
coordinate it as an explicit repo-maintenance task, then rerun both scanner
commands and the full readiness suite before pushing.
