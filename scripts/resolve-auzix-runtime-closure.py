#!/usr/bin/env python3
"""Print an ordered AUZiX dependency closure from repository metadata."""

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("index", type=Path)
    parser.add_argument("roots", nargs="+")
    args = parser.parse_args()

    packages = json.loads(args.index.read_text()).get("packages", [])
    by_name = {str(item["name"]).casefold(): item for item in packages}
    visiting: set[str] = set()
    seen: set[str] = set()
    ordered: list[str] = []

    def visit(name: str) -> None:
        key = name.casefold()
        if key in seen or key in visiting:
            return
        item = by_name.get(key)
        if item is None:
            raise SystemExit(f"dependency absent from repository: {name}")
        visiting.add(key)
        for dependency in item.get("depends") or []:
            visit(str(dependency))
        visiting.remove(key)
        seen.add(key)
        ordered.append(str(item["name"]))

    for root in args.roots:
        visit(root)
    print(" ".join(ordered))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
