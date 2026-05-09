#!/usr/bin/env python3
"""Fail CI on tracked endpoint tokens or obvious key-file mistakes.

This is intentionally focused. The repo contains many legitimate 32-byte test
vectors, Starknet addresses, hashes, and devnet keys, so a generic high-entropy
scanner would produce too much noise. This check targets the production hygiene
mistakes that should never be committed:

- provider URLs with embedded API keys;
- query-string API keys/tokens;
- tracked local secret files;
- literal non-devnet private-key assignments.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


TOKEN_BEARING_URL_PATTERNS = (
    re.compile(
        r"https?://[^\s\"'<>]*(?:alchemy\.com|infura\.io|quicknode\.com|"
        r"getblock\.io|nownodes\.io|onfinality\.io|chainstack\.com|ankr\.com)"
        r"[^\s\"'<>]*(?:/|=)[A-Za-z0-9_-]{20,}",
        re.IGNORECASE,
    ),
    re.compile(
        r"https?://[^\s\"'<>]*(?:apikey|api_key|access_key|token|key)="
        r"[A-Za-z0-9_-]{20,}",
        re.IGNORECASE,
    ),
)

PRIVATE_KEY_ASSIGNMENT = re.compile(
    r"(?i)(private[_ -]?key|STARKNET_PRIVATE_KEY|RELAY_PRIVATE_KEY|RELAYER_PARTIAL_[A-Z0-9_]+)"
    r"\s*[:=]\s*[\"']?(0x)?([0-9a-f]{64})"
)

SENSITIVE_TRACKED_BASENAMES = {
    ".deployer_key",
    ".env",
    "claim-relayer.secrets",
    "starknet_open_zeppelin_accounts.json",
}

DEVNET_KEY_PREFIX = "00000000000000000000000000000000"


def git_ls_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return [Path(line) for line in result.stdout.splitlines() if line]


def is_text_file(path: Path) -> bool:
    try:
        chunk = path.read_bytes()[:4096]
    except OSError:
        return False
    return b"\0" not in chunk


def is_allowed_private_key_hit(path: Path, line: str, key_hex: str) -> bool:
    lowered_path = str(path).lower()
    lowered_line = line.lower()
    if "devnet" in lowered_path or "devnet" in lowered_line:
        return True
    if key_hex.lower().startswith(DEVNET_KEY_PREFIX):
        return True
    if "<private_key" in lowered_line or "your_hex_key" in lowered_line:
        return True
    return False


def scan_file(path: Path) -> list[str]:
    findings: list[str] = []
    if path.name in SENSITIVE_TRACKED_BASENAMES and not path.name.endswith(".example"):
        findings.append(f"{path}: tracked sensitive local file name")

    if not is_text_file(path):
        return findings

    try:
        content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        content = path.read_text(encoding="utf-8", errors="ignore")

    for line_no, line in enumerate(content.splitlines(), start=1):
        for pattern in TOKEN_BEARING_URL_PATTERNS:
            if pattern.search(line):
                findings.append(f"{path}:{line_no}: token-bearing provider URL")

        private_key_match = PRIVATE_KEY_ASSIGNMENT.search(line)
        if private_key_match:
            key_hex = private_key_match.group(3)
            if not is_allowed_private_key_hit(path, line, key_hex):
                findings.append(f"{path}:{line_no}: literal private-key assignment")

    return findings


def main() -> int:
    findings: list[str] = []
    for path in git_ls_files():
        findings.extend(scan_file(path))

    if findings:
        print("Secret hygiene check failed:", file=sys.stderr)
        for finding in findings:
            print(f"  - {finding}", file=sys.stderr)
        return 1

    print("Secret hygiene check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
