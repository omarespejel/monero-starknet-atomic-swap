#!/usr/bin/env python3
"""Verify a redacted claim-relayer handoff packet.

This is the receiver-side check for second-operator takeover drills. It does
not prove the Monero funding output is spendable, but it catches malformed
packets, unredacted obvious secret-bearing URLs, invalid cursors, missing
artifact checksums, and unsafe secrets-file permissions.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


EXPECTED_PURPOSE = "claim-relayer second-operator handoff"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
LONG_TOKEN_URL_RE = re.compile(r"https?://[^\s\"']+/[A-Za-z0-9_-]{20,}")
SECRET_FILE_SUFFIX = "/claim-relayer.secrets"


class FindingCollector:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


def is_sha256(value: Any) -> bool:
    return isinstance(value, str) and bool(SHA256_RE.fullmatch(value))


def iter_strings(value: Any) -> list[str]:
    strings: list[str] = []
    if isinstance(value, dict):
        for item in value.values():
            strings.extend(iter_strings(item))
    elif isinstance(value, list):
        for item in value:
            strings.extend(iter_strings(item))
    elif isinstance(value, str):
        strings.append(value)
    return strings


def validate_config(packet: dict[str, Any], findings: FindingCollector) -> None:
    config = packet.get("config")
    if not isinstance(config, dict):
        findings.error("missing config object")
        return

    if not is_sha256(config.get("sha256")):
        findings.error("config.sha256 is missing or invalid")

    defaults = config.get("defaults")
    if not isinstance(defaults, dict):
        findings.error("config.defaults is missing or not an object")

    locks = config.get("locks")
    discoveries = config.get("discoveries")
    if not isinstance(locks, list):
        findings.error("config.locks is missing or not a list")
        locks = []
    if not isinstance(discoveries, list):
        findings.error("config.discoveries is missing or not a list")
        discoveries = []
    if not locks and not discoveries:
        findings.error("packet has no locks or discoveries")

    cursor_dir = config.get("cursor_dir")
    if isinstance(cursor_dir, dict):
        entries = cursor_dir.get("entries") or []
        if not isinstance(entries, list):
            findings.error("config.cursor_dir.entries is not a list")
        else:
            for cursor in entries:
                validate_cursor(cursor, findings, prefix="config.cursor_dir")
    elif cursor_dir is not None:
        findings.error("config.cursor_dir is not an object")

    for index, lock in enumerate(locks):
        if not isinstance(lock, dict):
            findings.error(f"config.locks[{index}] is not an object")
            continue
        cursor = lock.get("cursor")
        if cursor is not None:
            validate_cursor(cursor, findings, prefix=f"config.locks[{index}]")


def validate_cursor(cursor: Any, findings: FindingCollector, prefix: str) -> None:
    if not isinstance(cursor, dict):
        findings.error(f"{prefix}.cursor is not an object")
        return
    if not cursor.get("exists"):
        return
    if cursor.get("json_valid") is not True:
        findings.error(f"{prefix} cursor exists but is not valid JSON: {cursor.get('path')}")
    if not is_sha256(cursor.get("sha256")):
        findings.error(f"{prefix} cursor exists but sha256 is missing or invalid: {cursor.get('path')}")


def validate_artifacts(
    packet: dict[str, Any], findings: FindingCollector, require_artifact: bool
) -> None:
    artifacts = packet.get("artifacts")
    if artifacts is None:
        if require_artifact:
            findings.error("artifacts list is missing")
        return
    if not isinstance(artifacts, list):
        findings.error("artifacts is not a list")
        return

    existing = 0
    for index, artifact in enumerate(artifacts):
        if not isinstance(artifact, dict):
            findings.error(f"artifacts[{index}] is not an object")
            continue
        if artifact.get("exists"):
            existing += 1
            if not is_sha256(artifact.get("sha256")):
                findings.error(f"artifacts[{index}] exists but sha256 is missing or invalid")

    if require_artifact and existing == 0:
        findings.error("no existing artifact with checksum was included")


def validate_presence_files(packet: dict[str, Any], findings: FindingCollector) -> None:
    files = packet.get("presence_files")
    if files is None:
        findings.warn("presence_files list is missing")
        return
    if not isinstance(files, list):
        findings.error("presence_files is not a list")
        return

    for index, item in enumerate(files):
        if not isinstance(item, dict):
            findings.error(f"presence_files[{index}] is not an object")
            continue
        path = str(item.get("path") or "")
        if path.endswith(SECRET_FILE_SUFFIX) and item.get("exists") and item.get("mode") != "0o600":
            findings.error(f"{path} exists but mode is {item.get('mode')}, expected 0o600")


def validate_systemd(packet: dict[str, Any], findings: FindingCollector) -> None:
    services = packet.get("systemd")
    if services is None:
        findings.warn("systemd status list is missing")
        return
    if not isinstance(services, list):
        findings.error("systemd is not a list")
        return
    for index, service in enumerate(services):
        if not isinstance(service, dict):
            findings.error(f"systemd[{index}] is not an object")
            continue
        if not service.get("name"):
            findings.error(f"systemd[{index}] missing service name")


def validate_redaction(packet: dict[str, Any], findings: FindingCollector) -> None:
    for value in iter_strings(packet):
        if "<redacted>" in value:
            continue
        if LONG_TOKEN_URL_RE.search(value):
            findings.error(f"possible unredacted token-bearing URL: {value}")


def validate_packet(args: argparse.Namespace, packet: dict[str, Any]) -> FindingCollector:
    findings = FindingCollector()
    if packet.get("purpose") != EXPECTED_PURPOSE:
        findings.error(f"unexpected purpose: {packet.get('purpose')!r}")
    if not packet.get("generated_at_utc"):
        findings.error("missing generated_at_utc")

    validate_config(packet, findings)
    validate_artifacts(packet, findings, args.require_artifact)
    validate_presence_files(packet, findings)
    validate_systemd(packet, findings)
    validate_redaction(packet, findings)

    packet_warnings = packet.get("warnings") or []
    if not isinstance(packet_warnings, list):
        findings.error("warnings is not a list")
    elif packet_warnings:
        message = "; ".join(str(item) for item in packet_warnings)
        if args.strict_warnings:
            findings.error(f"packet warnings present: {message}")
        else:
            findings.warn(f"packet warnings present: {message}")

    return findings


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("packet", help="handoff packet JSON path")
    parser.add_argument(
        "--require-artifact",
        action="store_true",
        help="fail unless at least one existing artifact with sha256 is present",
    )
    parser.add_argument(
        "--strict-warnings",
        action="store_true",
        help="treat packet warnings as verification failures",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    path = Path(args.packet)
    packet = json.loads(path.read_text())
    findings = validate_packet(args, packet)

    for warning in findings.warnings:
        print(f"WARN {warning}", file=sys.stderr)
    for error in findings.errors:
        print(f"FAIL {error}", file=sys.stderr)

    if findings.errors:
        print(f"handoff packet verification failed: {len(findings.errors)} issue(s)", file=sys.stderr)
        return 1

    print(
        f"handoff packet verification passed: warnings={len(findings.warnings)} "
        f"artifacts={len(packet.get('artifacts') or [])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
