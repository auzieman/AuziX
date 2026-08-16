#!/usr/bin/env python3
"""Extract Debian maintainer-script shell snippets into AUZiX lifecycle fragments.

Debian maintainer scripts are evidence, not AUZiX policy. This tool preserves
the relevant shell decisions and classifies them so AUZiX can translate them
into idempotent setup/fix hooks.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys


PATTERNS = {
    "users_groups": re.compile(r"\b(adduser|useradd|groupadd|chown|chmod|install\s+-[^\n]*[omg]|dpkg-statoverride)\b"),
    "dbus": re.compile(r"\b(dbus|dbus-daemon|dbus-send|system_bus_socket)\b|/dbus-1/"),
    "polkit": re.compile(r"\b(polkit|pkexec|pkaction|pkcheck)\b|/polkit-1/"),
    "systemd": re.compile(r"\b(systemctl|deb-systemd-helper|deb-systemd-invoke|invoke-rc\.d|service)\b|/systemd/"),
    "tmpfiles": re.compile(r"\b(systemd-tmpfiles|tmpfiles\.d)\b"),
    "schemas": re.compile(r"\b(glib-compile-schemas|gsettings)\b|/glib-2\.0/schemas/"),
    "icons": re.compile(r"\b(gtk-update-icon-cache|update-icon-caches)\b|/icons/"),
    "desktop_database": re.compile(r"\b(update-desktop-database)\b|/applications/"),
    "mime": re.compile(r"\b(update-mime-database|update-mime)\b|/mime/"),
    "ldconfig": re.compile(r"\bldconfig\b"),
    "capabilities": re.compile(r"\b(setcap|getcap|capabilities)\b"),
    "path_assumption": re.compile(r"(?<![A-Za-z0-9_])/(usr|etc|var|bin|sbin|lib|run|tmp|root)(/|[\"' ]|$)"),
}

HOOKS = {
    "users_groups": "user/group/mode.ensure",
    "dbus": "dbus.install-service-or-ensure-bus",
    "polkit": "polkit.install-policy-or-ensure-daemon",
    "systemd": "service.translate-enable-start",
    "tmpfiles": "state.ensure-dir-from-tmpfiles",
    "schemas": "gsettings.compile-schemas",
    "icons": "xdg.refresh-icon-cache",
    "desktop_database": "xdg.refresh-desktop-database",
    "mime": "xdg.refresh-mime-database",
    "ldconfig": "runtime-ladder.register",
    "capabilities": "capability.ensure",
    "path_assumption": "path.map-before-package-bake-in",
}


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""


def continuation_blocks(lines: list[str]) -> list[tuple[int, str]]:
    blocks: list[tuple[int, str]] = []
    current: list[str] = []
    start = 0
    for idx, line in enumerate(lines, 1):
        stripped = line.rstrip()
        if not current:
            start = idx
        current.append(stripped)
        if stripped.endswith("\\"):
            continue
        text = "\n".join(current).strip()
        if text and not text.startswith("#"):
            blocks.append((start, text))
        current = []
    return blocks


def classify(text: str) -> list[str]:
    return [name for name, pattern in PATTERNS.items() if pattern.search(text)]


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: extract-lifecycle-shell-fragments.py <lifecycle-out-dir> [out-json]", file=sys.stderr)
        return 2

    lifecycle_dir = pathlib.Path(sys.argv[1]).resolve()
    control_dir = lifecycle_dir / "extract" / "control"
    package = lifecycle_dir.name
    for line in read(control_dir / "control").splitlines():
        if line.startswith("Package:"):
            package = line.split(":", 1)[1].strip()
            break

    fragments = []
    for script_name in ("preinst", "postinst", "prerm", "postrm", "triggers"):
        script = read(control_dir / script_name)
        if not script:
            continue
        for line_no, block in continuation_blocks(script.splitlines()):
            classes = classify(block)
            if not classes:
                continue
            fragments.append({
                "script": script_name,
                "line": line_no,
                "classes": classes,
                "suggested_hooks": [HOOKS[name] for name in classes],
                "shell": block,
                "replay_policy": "translate-only"
            })

    out_data = {
        "format": "auzix-lifecycle-shell-fragments-v1",
        "package": package,
        "source": str(lifecycle_dir),
        "policy": {
            "execute_raw_shell": False,
            "translate_into_idempotent_hooks": True,
            "preserve_original_for_audit": True
        },
        "fragments": fragments
    }

    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else lifecycle_dir / "report" / f"{package}.shell-fragments.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(out_data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

