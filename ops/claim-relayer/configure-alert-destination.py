#!/usr/bin/env python3
"""Configure claim relayer alert destination without printing webhook secrets."""

from __future__ import annotations

import argparse
import os
import stat
import sys
import tempfile
from pathlib import Path


DEFAULT_ENV_FILE = Path("/etc/atomic-swap/claim-relayer-healthcheck.env")
MANAGED_KEYS = (
    "RELAYER_ALERT_WEBHOOK_URL",
    "RELAYER_ALERT_FILE",
    "RELAYER_ALERT_ENVIRONMENT",
    "RELAYER_ALERT_FORMAT",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--env-file",
        type=Path,
        default=DEFAULT_ENV_FILE,
        help=f"healthcheck env file to update (default: {DEFAULT_ENV_FILE})",
    )
    webhook = parser.add_mutually_exclusive_group()
    webhook.add_argument(
        "--webhook-stdin",
        action="store_true",
        help="read RELAYER_ALERT_WEBHOOK_URL from stdin; avoids shell history",
    )
    webhook.add_argument(
        "--webhook-url",
        help="set RELAYER_ALERT_WEBHOOK_URL from this argument; stdin is safer",
    )
    webhook.add_argument(
        "--clear-webhook",
        action="store_true",
        help="clear RELAYER_ALERT_WEBHOOK_URL",
    )
    alert_file = parser.add_mutually_exclusive_group()
    alert_file.add_argument("--alert-file", help="set RELAYER_ALERT_FILE")
    alert_file.add_argument(
        "--clear-alert-file",
        action="store_true",
        help="clear RELAYER_ALERT_FILE",
    )
    parser.add_argument("--environment", help="set RELAYER_ALERT_ENVIRONMENT")
    parser.add_argument(
        "--format",
        choices=("slack", "firehydrant"),
        help="set RELAYER_ALERT_FORMAT",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate and print redacted summary without writing",
    )
    return parser.parse_args()


def read_env_file(path: Path) -> list[str]:
    if not path.exists():
        return []
    return path.read_text(encoding="utf-8").splitlines()


def read_webhook_from_stdin() -> str:
    value = sys.stdin.readline().strip()
    if not value:
        raise SystemExit("empty webhook URL on stdin")
    return value


def validate_value(name: str, value: str) -> None:
    if "\n" in value or "\r" in value:
        raise SystemExit(f"{name} must be a single line")
    if any(char.isspace() for char in value):
        raise SystemExit(f"{name} must not contain whitespace")


def env_line(name: str, value: str) -> str:
    validate_value(name, value)
    return f"{name}={value}"


def merge_env(lines: list[str], updates: dict[str, str]) -> list[str]:
    output: list[str] = []
    seen: set[str] = set()
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in line:
            output.append(line)
            continue
        key = line.split("=", 1)[0].strip()
        if key in MANAGED_KEYS and key in updates:
            output.append(env_line(key, updates[key]))
            seen.add(key)
        else:
            output.append(line)

    missing = [key for key in MANAGED_KEYS if key in updates and key not in seen]
    if missing and output and output[-1].strip():
        output.append("")
    for key in missing:
        output.append(env_line(key, updates[key]))
    return output


def write_locked_env(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = 0o600
    uid = os.getuid()
    gid = os.getgid()
    if path.exists():
        current = path.stat()
        mode = stat.S_IMODE(current.st_mode)
        uid = current.st_uid
        gid = current.st_gid

    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        delete=False,
    ) as handle:
        tmp_path = Path(handle.name)
        handle.write("\n".join(lines).rstrip() + "\n")

    os.chmod(tmp_path, 0o600)
    try:
        os.chown(tmp_path, uid, gid)
    except PermissionError:
        pass
    os.replace(tmp_path, path)
    os.chmod(path, mode if mode & 0o077 == 0 else 0o600)


def main() -> int:
    args = parse_args()
    updates: dict[str, str] = {}

    if args.webhook_stdin:
        updates["RELAYER_ALERT_WEBHOOK_URL"] = read_webhook_from_stdin()
    elif args.webhook_url is not None:
        updates["RELAYER_ALERT_WEBHOOK_URL"] = args.webhook_url.strip()
    elif args.clear_webhook:
        updates["RELAYER_ALERT_WEBHOOK_URL"] = ""

    if args.alert_file is not None:
        updates["RELAYER_ALERT_FILE"] = args.alert_file.strip()
    elif args.clear_alert_file:
        updates["RELAYER_ALERT_FILE"] = ""

    if args.environment is not None:
        updates["RELAYER_ALERT_ENVIRONMENT"] = args.environment.strip()
    if args.format is not None:
        updates["RELAYER_ALERT_FORMAT"] = args.format

    if not updates:
        raise SystemExit("no alert destination changes requested")

    for key, value in updates.items():
        validate_value(key, value)

    merged = merge_env(read_env_file(args.env_file), updates)
    if not args.dry_run:
        write_locked_env(args.env_file, merged)

    webhook_state = "unchanged"
    if "RELAYER_ALERT_WEBHOOK_URL" in updates:
        webhook_state = "set" if updates["RELAYER_ALERT_WEBHOOK_URL"] else "cleared"
    file_state = "unchanged"
    if "RELAYER_ALERT_FILE" in updates:
        file_state = "set" if updates["RELAYER_ALERT_FILE"] else "cleared"
    env_state = updates.get("RELAYER_ALERT_ENVIRONMENT", "unchanged")
    format_state = updates.get("RELAYER_ALERT_FORMAT", "unchanged")
    action = "would update" if args.dry_run else "updated"
    print(
        f"{action} {args.env_file}: "
        f"webhook={webhook_state} alert_file={file_state} "
        f"environment={env_state} format={format_state}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
