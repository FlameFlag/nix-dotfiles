#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p "python3.withPackages (ps: [ ps.sqlcipher3 ])"
from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from contextlib import closing
from pathlib import Path

import sqlcipher3


EXTENSION_ID = "builtin_package_windowManagement"
COMMAND_PREFIX = "builtin_command_windowManagement"


def load_config(path: Path) -> tuple[dict[str, str | None], list[str]]:
    with path.open(encoding="utf-8") as handle:
        config = json.load(handle)

    if not isinstance(config, dict):
        raise ValueError("config must be an object")

    raw_hotkeys = config.get("hotkeys", {})
    if not isinstance(raw_hotkeys, dict):
        raise ValueError("hotkeys must be an object")

    hotkeys: dict[str, str | None] = {}
    for key, hotkey in raw_hotkeys.items():
        if not isinstance(key, str) or not key.startswith(COMMAND_PREFIX):
            raise ValueError(f"invalid window-management command in hotkeys: {key!r}")
        if hotkey is not None and not isinstance(hotkey, str):
            raise ValueError(f"invalid hotkey for {key}: {hotkey!r}")
        hotkeys[key] = hotkey

    disabled_commands = config.get("disabledCommands", [])
    if not isinstance(disabled_commands, list) or not all(
        isinstance(command, str) for command in disabled_commands
    ):
        raise ValueError("disabledCommands must be a list of strings")

    for command in disabled_commands:
        if not command.startswith(COMMAND_PREFIX):
            raise ValueError(
                f"invalid window-management command in disabledCommands: {command!r}"
            )

    return hotkeys, disabled_commands


def apply_config(
    connection,
    hotkeys: dict[str, str | None],
    disabled_commands: list[str],
) -> None:
    rows = connection.execute(
        "SELECT key FROM search WHERE key LIKE ?",
        (f"{COMMAND_PREFIX}%",),
    )
    missing = sorted(
        (set(hotkeys) | set(disabled_commands))
        - {row[0] for row in rows}
    )
    if missing:
        raise ValueError(
            "Raycast database does not contain configured command(s): "
            + ", ".join(missing)
        )

    with connection:
        connection.execute(
            "UPDATE search SET hotkey = NULL WHERE key LIKE ?",
            (f"{COMMAND_PREFIX}%",),
        )

        connection.executemany(
            "UPDATE search SET hotkey = ? WHERE key = ?",
            [(hotkey, key) for key, hotkey in sorted(hotkeys.items())],
        )

        connection.execute(
            """
            INSERT INTO raycastConfiguration (extensionId, configuration, updatedAt)
            VALUES (?, ?, strftime('%Y-%m-%d %H:%M:%f', 'now'))
            ON CONFLICT(extensionId) DO UPDATE SET
                configuration = excluded.configuration,
                updatedAt = excluded.updatedAt
            """,
            (
                EXTENSION_ID,
                json.dumps(
                    {"disabledCommands": disabled_commands},
                    separators=(",", ":"),
                ),
            ),
        )


def main(argv: Sequence[str] = sys.argv[1:]) -> int:
    parser = argparse.ArgumentParser(
        description="Apply Raycast window-management settings.",
    )
    parser.add_argument("database", type=Path, help="Path to raycast-enc.sqlite")
    parser.add_argument("config", type=Path, help="Path to window-management.json")
    args = parser.parse_args(argv)

    try:
        passphrase = sys.stdin.read().strip()
        if not passphrase:
            raise ValueError("database passphrase must be provided on stdin")
        if len(passphrase) != 64 or any(c not in "0123456789abcdef" for c in passphrase):
            raise ValueError(
                "database passphrase must be a 64-character lowercase hex digest"
            )

        hotkeys, disabled_commands = load_config(args.config)
        with closing(sqlcipher3.connect(str(args.database))) as connection:
            connection.execute(f'PRAGMA key = "{passphrase}"')
            apply_config(connection, hotkeys, disabled_commands)
    except (OSError, ValueError, sqlcipher3.DatabaseError) as error:
        print(f"{Path(sys.argv[0]).name}: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
