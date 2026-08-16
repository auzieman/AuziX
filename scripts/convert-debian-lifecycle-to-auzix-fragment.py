#!/usr/bin/env python3
"""Convert extracted Debian package lifecycle evidence into an AUZiX fragment.

Input is the output directory from scripts/extract-debian-package-lifecycle.sh.
The result is intentionally a fragment, not a final package recipe: it captures
what Debian says must exist, then names the AUZiX surfaces that need mapping.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any


DONOR_PATH_MAP = {
    "/usr/bin": "/Programs/<Package>/current/Commands",
    "/usr/sbin": "/Programs/<Package>/current/AdminCommands",
    "/usr/libexec": "/Programs/<Package>/current/Helpers",
    "/usr/lib": "/Programs/<Package>/current/Libraries",
    "/lib": "/Programs/<Package>/current/Libraries",
    "/usr/share": "/Programs/<Package>/current/Shared",
    "/etc": "/System/Settings",
    "/var/lib": "/System/State",
    "/var/cache": "/System/Cache",
    "/var/log": "/System/Logs",
    "/run": "/System/Run",
    "/tmp": "/Work/Temp",
    "/root": "/Users/root",
}

SERVICE_PATTERNS = {
    "dbus": re.compile(r"dbus|/usr/share/dbus-1", re.I),
    "polkit": re.compile(r"polkit|/usr/share/polkit-1", re.I),
    "systemd": re.compile(r"systemctl|systemd|/systemd/system", re.I),
    "schemas": re.compile(r"glib-compile-schemas|gsettings|/glib-2.0/schemas", re.I),
    "icons": re.compile(r"gtk-update-icon-cache|/usr/share/icons", re.I),
    "desktop_database": re.compile(r"update-desktop-database|/usr/share/applications", re.I),
    "mime": re.compile(r"update-mime|/usr/share/mime", re.I),
    "users_groups": re.compile(r"adduser|useradd|groupadd|chown|chmod|setuid|setgid", re.I),
    "capabilities": re.compile(r"setcap|capabilities", re.I),
    "ldconfig": re.compile(r"ldconfig", re.I),
}


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""


def read_lines(path: pathlib.Path) -> list[str]:
    text = read(path)
    return [line.strip() for line in text.splitlines() if line.strip()]


def parse_control(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    key: str | None = None
    for line in text.splitlines():
        if line.startswith((" ", "\t")) and key:
            out[key] += " " + line.strip()
        elif ":" in line:
            key, value = line.split(":", 1)
            out[key] = value.strip()
    return out


def split_deps(value: str) -> list[Any]:
    if not value:
        return []
    deps: list[Any] = []
    for raw in value.split(","):
        cleaned = re.sub(r"\[[^\]]*\]|<[^>]*>|\([^)]*\)", "", raw).strip()
        if not cleaned:
            continue
        alts = [part.strip() for part in cleaned.split("|") if part.strip()]
        deps.append(alts if len(alts) > 1 else alts[0])
    return deps


def donor_paths(text: str) -> list[str]:
    found: set[str] = set()
    for match in re.finditer(r"(?<![A-Za-z0-9_])(/(?:usr|etc|var|bin|sbin|lib|run|tmp|root)(?:/[A-Za-z0-9._+@%:=,-]+)*)", text):
        found.add(match.group(1))
    return sorted(found)


def classify_surfaces(text: str, surfaces: list[str]) -> dict[str, bool]:
    combined = text + "\n" + "\n".join(surfaces)
    return {name: bool(pattern.search(combined)) for name, pattern in SERVICE_PATTERNS.items()}


def suggested_map(paths: list[str]) -> dict[str, str]:
    mapped: dict[str, str] = {}
    for path in paths:
        for donor, auzix in sorted(DONOR_PATH_MAP.items(), key=lambda item: len(item[0]), reverse=True):
            if path == donor or path.startswith(donor + "/"):
                suffix = path[len(donor):]
                mapped[path] = auzix + suffix
                break
    return mapped


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: convert-debian-lifecycle-to-auzix-fragment.py <lifecycle-out-dir> [out-json]", file=sys.stderr)
        return 2

    lifecycle_dir = pathlib.Path(sys.argv[1]).resolve()
    control_dir = lifecycle_dir / "extract" / "control"
    report_dir = lifecycle_dir / "report"

    control = parse_control(read(control_dir / "control"))
    package = control.get("Package") or lifecycle_dir.name
    lifecycle_signals = read(report_dir / "lifecycle-signals.txt")
    commands = read_lines(report_dir / "commands.txt")
    surfaces = read_lines(report_dir / "desktop-service-data.txt")
    files = read_lines(report_dir / "files.txt")

    maintainer_scripts: dict[str, str] = {}
    for name in ("preinst", "postinst", "prerm", "postrm", "triggers", "conffiles"):
        text = read(control_dir / name)
        if text:
            maintainer_scripts[name] = text

    paths = donor_paths(lifecycle_signals + "\n" + "\n".join(files))
    fragment = {
        "format": "auzix-debian-lifecycle-fragment-v1",
        "package": package,
        "source": {
            "type": "debian-binary-package",
            "lifecycle_dir": str(lifecycle_dir),
            "version": control.get("Version"),
            "architecture": control.get("Architecture"),
        },
        "debian": {
            "depends": split_deps(control.get("Depends", "")),
            "pre_depends": split_deps(control.get("Pre-Depends", "")),
            "recommends": split_deps(control.get("Recommends", "")),
            "suggests": split_deps(control.get("Suggests", "")),
            "maintainer_scripts": sorted(maintainer_scripts),
            "commands": commands,
            "desktop_service_data": surfaces,
        },
        "auzix_contract": {
            "donor_paths_observed": paths,
            "suggested_path_map": suggested_map(paths),
            "lifecycle_surfaces": classify_surfaces(lifecycle_signals, surfaces),
            "required_runtime_ladder": [
                "package-local RootFS/Commands/Libraries",
                "declared dependency packages in dependency order",
                "named shared runtime stacks when present",
                "/System/Compatibility and /System/Libraries only as explicit compatibility contracts",
            ],
            "required_install_hooks": [],
            "validation_probes": [],
            "open_questions": [],
        },
    }

    surfaces_found = fragment["auzix_contract"]["lifecycle_surfaces"]
    hooks = fragment["auzix_contract"]["required_install_hooks"]
    if surfaces_found["schemas"]:
        hooks.append("compile-or-export-gsettings-schemas")
    if surfaces_found["icons"]:
        hooks.append("refresh-icon-cache-or-export-theme-index")
    if surfaces_found["desktop_database"]:
        hooks.append("refresh-desktop-database-and-e-menu")
    if surfaces_found["mime"]:
        hooks.append("refresh-mime-database")
    if surfaces_found["dbus"]:
        hooks.append("install-dbus-service-and-ensure-session/system-bus-contract")
    if surfaces_found["polkit"]:
        hooks.append("install-polkit-policy-and-polkitd-contract")
    if surfaces_found["systemd"]:
        hooks.append("translate-systemd-unit-to-auzix-service-contract-or-compatibility")
    if surfaces_found["users_groups"]:
        hooks.append("apply-users-groups-modes-ownerships")
    if surfaces_found["capabilities"]:
        hooks.append("apply-file-capabilities-or-record-unsupported")
    if surfaces_found["ldconfig"]:
        hooks.append("replace-ldconfig-with-wrapper/runtime-ladder-receipt")

    probes = fragment["auzix_contract"]["validation_probes"]
    for command in commands[:8]:
        name = pathlib.PurePosixPath(command).name
        probes.append({
            "kind": "front-door-command",
            "debian_path": "/" + command,
            "auzix_path": f"/Programs/{package}/current/Commands/{name}",
            "probe": f"{name} --version || {name} --help",
        })
    for surface in surfaces:
        if surface.endswith(".desktop"):
            probes.append({"kind": "desktop-entry", "path": surface, "require_auzix_exec": True})

    if "/usr/bin" in "\n".join(commands) or commands:
        fragment["auzix_contract"]["open_questions"].append(
            "Does the command self-exec or canonicalize argv[0]? If yes, wrapper must preserve a real package-local executable path."
        )

    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else report_dir / f"{package}.auzix-fragment.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(fragment, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

