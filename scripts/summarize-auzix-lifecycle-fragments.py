#!/usr/bin/env python3
"""Summarize AUZiX lifecycle fragments into a stack-level expected-state plan."""

from __future__ import annotations

import json
import pathlib
import sys


STACK_ORDER = [
    "desktop-dbus-session",
    "desktop-polkit-session",
    "desktop-login-session",
    "desktop-efl-session",
    "desktop-enlightenment-session",
    "desktop-audio-session",
    "desktop-xdg-portals",
    "desktop-flatpak-system",
]


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "out/package-slices")
    out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "out/package-slices/desktop-lifecycle-stack-plan.json")
    fragments = []
    for path in sorted(root.glob("*/auzix-fragments/*.json")):
        data = json.loads(path.read_text())
        slice_id = path.parts[-3]
        contract = data.get("auzix_contract", {})
        fragments.append({
            "slice": slice_id,
            "package": data.get("package"),
            "fragment": str(path),
            "commands": data.get("debian", {}).get("commands", []),
            "hooks": contract.get("required_install_hooks", []),
            "surfaces": [
                name for name, enabled in contract.get("lifecycle_surfaces", {}).items()
                if enabled
            ],
            "validation_probes": contract.get("validation_probes", []),
            "suggested_path_map": contract.get("suggested_path_map", {}),
        })

    order = {name: i for i, name in enumerate(STACK_ORDER)}
    fragments.sort(key=lambda item: (order.get(item["slice"], 999), item["package"] or ""))

    hooks = {}
    surfaces = {}
    for item in fragments:
        for hook in item["hooks"]:
            hooks.setdefault(hook, []).append(item["package"])
        for surface in item["surfaces"]:
            surfaces.setdefault(surface, []).append(item["package"])

    plan = {
        "format": "auzix-lifecycle-stack-plan-v1",
        "stack": "desktop-session",
        "source": str(root),
        "dependency_order": STACK_ORDER,
        "summary": {
            "package_count": len(fragments),
            "hooks": {k: sorted(set(v)) for k, v in sorted(hooks.items())},
            "surfaces": {k: sorted(set(v)) for k, v in sorted(surfaces.items())},
        },
        "packages": fragments,
        "auzix_pkg_modes": {
            "setup": "Apply declared lifecycle hooks in dependency order after package extraction.",
            "fix": "Collect host state, compare to this plan, apply safe idempotent hooks, and record drift.",
        },
    }

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

