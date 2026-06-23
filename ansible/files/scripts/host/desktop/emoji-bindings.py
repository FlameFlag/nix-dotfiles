#!/usr/bin/env python3
from __future__ import annotations

import ast
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: emoji-bindings.py BINDING_PATH CURRENT_BINDINGS")

    binding_path = sys.argv[1]
    current = sys.argv[2].strip()

    if current.startswith("@as "):
        current = current[4:].strip()

    try:
        bindings = ast.literal_eval(current)
    except (SyntaxError, ValueError):
        bindings = []

    if not isinstance(bindings, list):
        bindings = []

    bindings = [binding for binding in bindings if isinstance(binding, str)]
    if binding_path not in bindings:
        bindings.append(binding_path)

    print("[" + ", ".join(repr(binding) for binding in bindings) + "]")


if __name__ == "__main__":
    main()
