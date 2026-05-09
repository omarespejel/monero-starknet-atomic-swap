#!/usr/bin/env python3
"""Run fast readiness checks and optionally write a reviewer-friendly report."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Check:
    name: str
    args: list[str]


FAST_CHECKS = (
    Check("git_status", ["git", "status", "--short", "--branch"]),
    Check("git_worktree_clean", ["bash", "-lc", 'test -z "$(git status --porcelain)"']),
    Check("git_diff_check", ["git", "diff", "--check"]),
    Check(
        "python_compile",
        [
            "python3",
            "-m",
            "py_compile",
            "tools/check_secret_hygiene.py",
            "tools/readiness_preflight.py",
            "ops/claim-relayer/claim-relayer-handoff-packet.py",
            "ops/claim-relayer/verify-handoff-packet.py",
            "ops/claim-relayer/configure-alert-destination.py",
        ],
    ),
    Check(
        "bash_syntax",
        [
            "bash",
            "-n",
            "scripts/deploy_with_sncast.sh",
            "scripts/atomic_lock_sncast_ops.sh",
            "scripts/monero_vm_tunnel.sh",
            "ops/claim-relayer/claim-relayer-alert.sh",
            "ops/claim-relayer/claim-relayer-healthcheck.sh",
            "ops/claim-relayer/run-handoff-drill.sh",
        ],
    ),
    Check("secret_hygiene_current", ["python3", "tools/check_secret_hygiene.py"]),
    Check(
        "secret_hygiene_history_report",
        ["python3", "tools/check_secret_hygiene.py", "--history", "--report-only"],
    ),
)

CAIRO_CHECKS = (
    Check("cairo_snforge_test", ["bash", "-lc", "cd cairo && snforge test"]),
)

RUST_CHECKS = (
    Check("rust_relayer_tests", ["bash", "-lc", "cd rust && cargo test -q --lib swap::relayer"]),
    Check(
        "rust_claim_relayer_service_tests",
        ["bash", "-lc", "cd rust && cargo test -q --bin claim_relayer_service"],
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="write JSON report to this path")
    parser.add_argument("--include-cairo", action="store_true", help="run snforge test")
    parser.add_argument("--include-rust", action="store_true", help="run focused Rust relayer tests")
    return parser.parse_args()


def run_check(check: Check) -> dict[str, Any]:
    result = subprocess.run(
        check.args,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return {
        "name": check.name,
        "command": check.args,
        "exit_code": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }


def git_value(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout.strip()


def build_report(checks: list[Check]) -> dict[str, Any]:
    results = [run_check(check) for check in checks]
    return {
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo_root": str(ROOT),
        "commit": git_value("rev-parse", "HEAD"),
        "branch": git_value("branch", "--show-current"),
        "passed": all(item["exit_code"] == 0 for item in results),
        "checks": results,
        "remaining_external_blockers": [
            "second operator handoff drill and signoff",
            "external security review before meaningful-value mainnet use",
        ],
    }


def print_summary(report: dict[str, Any]) -> None:
    status = "passed" if report["passed"] else "failed"
    print(f"readiness_preflight status={status} commit={report['commit'][:12]}")
    for item in report["checks"]:
        print(f"{item['name']} exit={item['exit_code']}")
    if report["remaining_external_blockers"]:
        print("remaining_external_blockers:")
        for blocker in report["remaining_external_blockers"]:
            print(f"- {blocker}")


def main() -> int:
    args = parse_args()
    checks = list(FAST_CHECKS)
    if args.include_cairo:
        checks.extend(CAIRO_CHECKS)
    if args.include_rust:
        checks.extend(RUST_CHECKS)

    report = build_report(checks)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print_summary(report)
    if args.output:
        print(f"report={args.output}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
