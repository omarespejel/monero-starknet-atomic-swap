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

import argparse
import io
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
# Keep this deliberately narrower than the current-tree scanner. Historical
# scans are used to find RPC-provider exposure evidence for rotation runbooks;
# literal private-key assignments are still blocked in the current tracked tree.
HISTORY_GREP_PATTERN = (
    r"alchemy\.com|infura\.io|quicknode\.com|getblock\.io|nownodes\.io|"
    r"onfinality\.io|chainstack\.com|ankr\.com|apikey|api_key|access_key|token="
)
EXCLUDED_HISTORY_PREFIXES = (
    "cairo/.scarb_cache/",
    "cairo/target/",
    "rust/target/",
    "scripts/ts/node_modules/",
    "node_modules/",
    "target/",
)
HISTORY_INCLUDE_PATHS = (
    "README.md",
    "docs",
    "scripts",
    "ops",
    ".github",
    "rust/src",
    "rust/tests",
    "watchtower",
    "cairo/snfoundry.toml",
    "cairo/Scarb.toml",
)
HISTORY_EXCLUDE_PATHS = (
    ":(exclude)cairo/.scarb_cache/**",
    ":(exclude)cairo/target/**",
    ":(exclude)rust/target/**",
    ":(exclude)scripts/ts/node_modules/**",
    ":(exclude)node_modules/**",
    ":(exclude)target/**",
)
HISTORY_PATHS = HISTORY_INCLUDE_PATHS + HISTORY_EXCLUDE_PATHS


def git_ls_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return [Path(line) for line in result.stdout.splitlines() if line]


def excluded_history_path(path: Path) -> bool:
    value = str(path)
    return any(value.startswith(prefix) for prefix in EXCLUDED_HISTORY_PREFIXES)


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


def sensitive_basename_finding(path: Path, prefix: str = "") -> str | None:
    if path.name in SENSITIVE_TRACKED_BASENAMES and not path.name.endswith(".example"):
        return f"{prefix}{path}: tracked sensitive local file name"
    return None


def scan_line(path: Path, line_no: int, line: str, prefix: str = "") -> list[str]:
    findings: list[str] = []
    for pattern in TOKEN_BEARING_URL_PATTERNS:
        if pattern.search(line):
            findings.append(f"{prefix}{path}:{line_no}: token-bearing provider URL")

    private_key_match = PRIVATE_KEY_ASSIGNMENT.search(line)
    if private_key_match:
        key_hex = private_key_match.group(3)
        if not is_allowed_private_key_hit(path, line, key_hex):
            findings.append(f"{prefix}{path}:{line_no}: literal private-key assignment")

    return findings


def scan_file(path: Path) -> list[str]:
    findings: list[str] = []
    sensitive_name = sensitive_basename_finding(path)
    if sensitive_name:
        findings.append(sensitive_name)

    if not is_text_file(path):
        return findings

    try:
        content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        content = path.read_text(encoding="utf-8", errors="ignore")

    for line_no, line in enumerate(content.splitlines(), start=1):
        findings.extend(scan_line(path, line_no, line))

    return findings


def scan_history_filenames() -> list[str]:
    findings: list[str] = []
    result = subprocess.run(
        [
            "git",
            "log",
            "--all",
            "--name-only",
            "--format=commit:%H",
            "--",
            ".",
            *HISTORY_EXCLUDE_PATHS,
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )

    revision = ""
    for raw in result.stdout.splitlines():
        if raw.startswith("commit:"):
            revision = raw.removeprefix("commit:")
            continue
        if not raw:
            continue
        path = Path(raw)
        if excluded_history_path(path):
            continue
        sensitive_name = sensitive_basename_finding(path, prefix=f"{revision[:12]}:")
        if sensitive_name:
            findings.append(sensitive_name)

    return findings


def history_blob_candidates() -> dict[str, list[tuple[str, Path]]]:
    result = subprocess.run(
        [
            "git",
            "log",
            "--all",
            "--raw",
            "--no-renames",
            "--abbrev=40",
            "--format=commit:%H",
            "--",
            *HISTORY_PATHS,
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )

    revision = ""
    blobs: dict[str, list[tuple[str, Path]]] = {}
    seen: set[tuple[str, str, Path]] = set()
    for raw in result.stdout.splitlines():
        if raw.startswith("commit:"):
            revision = raw.removeprefix("commit:")
            continue
        if not raw.startswith(":"):
            continue
        try:
            meta, path_text = raw.split("\t", 1)
        except ValueError:
            continue
        fields = meta.split()
        if len(fields) < 5:
            continue
        path = Path(path_text)
        if excluded_history_path(path):
            continue
        for blob_sha in (fields[2], fields[3]):
            if set(blob_sha) == {"0"}:
                continue
            item = (blob_sha, revision, path)
            if item in seen:
                continue
            seen.add(item)
            blobs.setdefault(blob_sha, []).append((revision, path))
    return blobs


def git_cat_file_batch(blob_shas: list[str]) -> dict[str, bytes]:
    if not blob_shas:
        return {}
    result = subprocess.run(
        ["git", "cat-file", "--batch"],
        input=("\n".join(blob_shas) + "\n").encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    stream = io.BytesIO(result.stdout)
    blobs: dict[str, bytes] = {}
    while True:
        header = stream.readline()
        if not header:
            break
        parts = header.decode("utf-8", errors="replace").strip().split()
        if len(parts) < 3 or parts[1] != "blob":
            continue
        blob_sha = parts[0]
        size = int(parts[2])
        data = stream.read(size)
        stream.read(1)
        blobs[blob_sha] = data
    return blobs


def scan_history_snapshots() -> list[str]:
    findings: list[str] = []
    blob_locations = history_blob_candidates()
    history_matcher = re.compile(HISTORY_GREP_PATTERN, re.IGNORECASE)
    for blob_sha, data in git_cat_file_batch(list(blob_locations)).items():
        if b"\0" in data[:4096]:
            continue
        content = data.decode("utf-8", errors="ignore")
        if not history_matcher.search(content):
            continue
        for revision, path in blob_locations[blob_sha]:
            for line_no, line in enumerate(content.splitlines(), start=1):
                if history_matcher.search(line):
                    findings.extend(scan_line(path, line_no, line, prefix=f"{revision[:12]}:"))
    return findings


def scan_history() -> list[str]:
    return scan_history_filenames() + scan_history_snapshots()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--history",
        action="store_true",
        help="scan reachable git history as well as the current tracked tree",
    )
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="print findings but exit 0; useful for known historical exposure runbooks",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    findings: list[str] = []
    for path in git_ls_files():
        findings.extend(scan_file(path))
    if args.history:
        findings.extend(scan_history())

    findings = sorted(set(findings))

    if findings:
        heading = "Secret hygiene findings:" if args.report_only else "Secret hygiene check failed:"
        print(heading, file=sys.stderr)
        for finding in findings:
            print(f"  - {finding}", file=sys.stderr)
        return 0 if args.report_only else 1

    print("Secret hygiene check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
