#!/usr/bin/env python3
"""Generate a redacted claim-relayer handoff packet.

The packet is intended for second-operator takeover drills. It records config,
cursor, service, and git metadata without printing partial spend keys, wallet
files, webhook URLs, or account secrets.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit, urlunsplit


DEFAULT_SERVICES = (
    "monero-claim-wallet-rpc.service",
    "monero-claim-relayer.service",
    "monero-claim-relayer-healthcheck.service",
    "monero-claim-relayer-healthcheck.timer",
)

DEFAULT_PRESENCE_FILES = (
    "/etc/atomic-swap/claim-relayer.env",
    "/etc/atomic-swap/claim-relayer.secrets",
    "/etc/atomic-swap/claim-relayer-healthcheck.env",
    "/etc/atomic-swap/monero-claim-wallet-rpc.env",
)

SENSITIVE_KEY_PARTS = (
    "private",
    "secret",
    "spend_key",
    "webhook",
    "token",
    "password",
    "passphrase",
)

SAFE_ENV_REFERENCE_KEYS = {
    "partial_spend_key_env",
    "partial_key_env_prefix",
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_mode(path: Path) -> str | None:
    try:
        mode = stat.S_IMODE(path.stat().st_mode)
    except OSError:
        return None
    return oct(mode)


def run(args: list[str], cwd: Path | None = None) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            args,
            cwd=str(cwd) if cwd else None,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError:
        return 127, "", f"{args[0]} not found"
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def redact_url(value: str) -> str:
    if "://" not in value:
        return value
    parts = urlsplit(value)
    netloc = parts.hostname or ""
    if parts.port:
        netloc = f"{netloc}:{parts.port}"
    if parts.username:
        netloc = f"{parts.username}:<redacted>@{netloc}"

    path_parts = parts.path.split("/")
    if path_parts:
        last = path_parts[-1]
        if len(last) >= 20 and re.fullmatch(r"[A-Za-z0-9_-]+", last):
            path_parts[-1] = "<redacted>"

    query = "<redacted>" if parts.query else ""
    return urlunsplit((parts.scheme, netloc, "/".join(path_parts), query, ""))


def sanitize_id(value: str) -> str:
    return "".join(ch if (ch.isascii() and (ch.isalnum() or ch in "_-")) else "_" for ch in value)


def cursor_path(defaults: dict[str, Any], lock: dict[str, Any]) -> Path:
    if lock.get("cursor_path"):
        return Path(lock["cursor_path"])
    cursor_dir = Path(defaults.get("cursor_dir") or ".relayer")
    return cursor_dir / f"{sanitize_id(str(lock.get('id', 'unnamed-lock')))}.json"


def cursor_metadata(path: Path) -> dict[str, Any]:
    metadata: dict[str, Any] = {"path": str(path), "exists": path.exists()}
    if not path.exists():
        return metadata
    stat_result = path.stat()
    metadata.update(
        {
            "size_bytes": stat_result.st_size,
            "mtime_utc": dt.datetime.fromtimestamp(stat_result.st_mtime, dt.timezone.utc)
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z"),
            "mode": oct(stat.S_IMODE(stat_result.st_mode)),
            "sha256": sha256_file(path),
        }
    )
    try:
        json.loads(path.read_text())
        metadata["json_valid"] = True
    except Exception as exc:  # noqa: BLE001 - this is diagnostic metadata.
        metadata["json_valid"] = False
        metadata["json_error"] = str(exc)
    return metadata


def cursor_dir_metadata(defaults: dict[str, Any]) -> dict[str, Any]:
    cursor_dir = Path(defaults.get("cursor_dir") or ".relayer")
    metadata: dict[str, Any] = {"path": str(cursor_dir), "exists": cursor_dir.exists(), "entries": []}
    if not cursor_dir.exists() or not cursor_dir.is_dir():
        return metadata
    for path in sorted(cursor_dir.glob("*.json")):
        metadata["entries"].append(cursor_metadata(path))
    return metadata


def presence_file_metadata(path: Path) -> dict[str, Any]:
    metadata: dict[str, Any] = {"path": str(path), "exists": path.exists()}
    if not path.exists():
        return metadata
    stat_result = path.stat()
    metadata.update(
        {
            "size_bytes": stat_result.st_size,
            "mode": oct(stat.S_IMODE(stat_result.st_mode)),
        }
    )
    return metadata


def artifact_metadata(path: Path) -> dict[str, Any]:
    metadata: dict[str, Any] = {"path": str(path), "exists": path.exists()}
    if not path.exists():
        return metadata
    stat_result = path.stat()
    metadata.update(
        {
            "size_bytes": stat_result.st_size,
            "mode": oct(stat.S_IMODE(stat_result.st_mode)),
            "sha256": sha256_file(path),
        }
    )
    return metadata


def service_status(service: str) -> dict[str, Any]:
    if shutil.which("systemctl") is None:
        return {"name": service, "available": False, "reason": "systemctl not found"}
    active_code, active, active_err = run(["systemctl", "is-active", service])
    enabled_code, enabled, enabled_err = run(["systemctl", "is-enabled", service])
    return {
        "name": service,
        "available": True,
        "active": active or active_err,
        "active_exit_code": active_code,
        "enabled": enabled or enabled_err,
        "enabled_exit_code": enabled_code,
    }


def git_metadata(repo_root: Path) -> dict[str, Any]:
    commit_code, commit, commit_err = run(["git", "rev-parse", "HEAD"], cwd=repo_root)
    status_code, status, status_err = run(["git", "status", "--short"], cwd=repo_root)
    branch_code, branch, branch_err = run(["git", "branch", "--show-current"], cwd=repo_root)
    return {
        "repo_root": str(repo_root),
        "commit": commit if commit_code == 0 else None,
        "commit_error": commit_err if commit_code != 0 else None,
        "branch": branch if branch_code == 0 else None,
        "branch_error": branch_err if branch_code != 0 else None,
        "dirty": bool(status) if status_code == 0 else None,
        "status_short": status.splitlines() if status else [],
        "status_error": status_err if status_code != 0 else None,
    }


def redacted_defaults(defaults: dict[str, Any]) -> dict[str, Any]:
    safe: dict[str, Any] = {}
    for key, value in defaults.items():
        lowered = key.lower()
        if isinstance(value, str) and (lowered.endswith("_url") or "rpc" in lowered):
            safe[key] = redact_url(value)
        else:
            safe[key] = value
    return safe


def redacted_lock(defaults: dict[str, Any], lock: dict[str, Any]) -> dict[str, Any]:
    allowed = {
        "id",
        "enabled",
        "contract_address",
        "start_block",
        "restore_height",
        "monero_network",
        "partial_spend_key_env",
        "confirmation_depth",
        "reorg_validation_depth",
        "max_blocks_per_batch",
        "retry_attempts",
        "retry_backoff_secs",
    }
    entry = {key: lock.get(key) for key in sorted(allowed) if key in lock}
    entry["cursor"] = cursor_metadata(cursor_path(defaults, lock))
    return entry


def redacted_discovery(discovery: dict[str, Any]) -> dict[str, Any]:
    allowed = {
        "id",
        "enabled",
        "registry_address",
        "start_block",
        "partial_key_env_prefix",
    }
    return {key: discovery.get(key) for key in sorted(allowed) if key in discovery}


def scan_for_secret_config(config: Any, path: str = "") -> list[str]:
    warnings: list[str] = []
    if isinstance(config, dict):
        for key, value in config.items():
            key_path = f"{path}.{key}" if path else str(key)
            lowered = str(key).lower()
            if any(part in lowered for part in SENSITIVE_KEY_PARTS) and key not in SAFE_ENV_REFERENCE_KEYS:
                warnings.append(f"review potentially sensitive config key: {key_path}")
            warnings.extend(scan_for_secret_config(value, key_path))
    elif isinstance(config, list):
        for index, value in enumerate(config):
            warnings.extend(scan_for_secret_config(value, f"{path}[{index}]"))
    return warnings


def build_packet(args: argparse.Namespace) -> dict[str, Any]:
    config_path = Path(args.config).expanduser().resolve()
    repo_root = Path(args.repo_root).expanduser().resolve()
    config = json.loads(config_path.read_text())
    defaults = config.get("defaults") or {}
    locks = config.get("locks") or []
    discoveries = config.get("discoveries") or []

    git = git_metadata(repo_root)
    warnings = scan_for_secret_config(config)
    if not git.get("commit"):
        warnings.append("repo_root did not resolve to a git checkout; verify artifact checksums")

    packet = {
        "generated_at_utc": utc_now(),
        "purpose": "claim-relayer second-operator handoff",
        "config": {
            "path": str(config_path),
            "mode": file_mode(config_path),
            "sha256": sha256_file(config_path),
            "defaults": redacted_defaults(defaults),
            "locks": [redacted_lock(defaults, lock) for lock in locks],
            "discoveries": [redacted_discovery(discovery) for discovery in discoveries],
            "cursor_dir": cursor_dir_metadata(defaults),
        },
        "git": git,
        "artifacts": [artifact_metadata(Path(path).expanduser()) for path in args.artifact],
        "presence_files": [
            presence_file_metadata(Path(path).expanduser()) for path in args.presence_file
        ],
        "systemd": [service_status(service) for service in args.service],
        "warnings": warnings,
        "operator_checks": [
            "Confirm any referenced partial_spend_key_env values exist in VM-local secrets, without copying the values into chat.",
            "Confirm Monero funding tx is mined, mature, and not double-spent before live claim.",
            "Run claim_relayer_service with --dry-run --once before starting a live takeover.",
            "Back up cursor files before editing or deleting them.",
            "Record Starknet claim tx and final token balance after claim_tokens.",
        ],
    }
    return packet


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        default="/etc/atomic-swap/claim-relayer.config.json",
        help="claim-relayer JSON config path",
    )
    parser.add_argument(
        "--repo-root",
        default=str(Path(__file__).resolve().parents[2]),
        help="repo root for git metadata",
    )
    parser.add_argument("--output", help="write packet to this file instead of stdout")
    parser.add_argument(
        "--artifact",
        action="append",
        default=[],
        help="installed binary or file to checksum in the handoff packet; may be repeated",
    )
    parser.add_argument(
        "--service",
        action="append",
        default=list(DEFAULT_SERVICES),
        help="systemd service/timer to include; may be repeated",
    )
    parser.add_argument(
        "--presence-file",
        action="append",
        default=list(DEFAULT_PRESENCE_FILES),
        help="file whose existence, mode, and size should be reported without hashing or reading content",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    packet = build_packet(args)
    rendered = json.dumps(packet, indent=2, sort_keys=True) + "\n"
    if args.output:
        output = Path(args.output).expanduser()
        output.write_text(rendered)
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
