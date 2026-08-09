#!/usr/bin/env python3
"""AUZiX workstation package watcher.

This is a promotion gate for desktop/workstation candidates.  It inspects
package receipts, commands, desktop entries, ELF dependency closure through
wrapper-visible runtime paths, strings-style donor path hits, and bounded smoke
commands where a known-safe probe exists.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import subprocess
from pathlib import Path
from typing import Any


SMOKE_ARGS = {
    "LibreOfficeCalc": ["--headless", "--version"],
    "LibreOfficeWriter": ["--headless", "--version"],
    "LibreOfficeDraw": ["--headless", "--version"],
    "LibreOfficeImpress": ["--headless", "--version"],
    "LibreOfficeMath": ["--headless", "--version"],
    "LibreOfficeBase": ["--headless", "--version"],
    "FirefoxEsr": ["--version"],
    "GIMP": ["--version"],
    "Inkscape": ["--version"],
    "Mpv": ["--version"],
    "VLC": ["--version"],
    "Audacious": ["--version"],
    "Geany": ["--version"],
    "Pluma": ["--version"],
    "Micro": ["-version"],
    "PCManFM": ["--version"],
    "Thunar": ["--version"],
    "GnomeDiskUtility": ["--version"],
    "Gparted": ["--version"],
    "GnomeControlCenter": ["--version"],
    "MateControlCenter": ["--version"],
    "Pavucontrol": ["--version"],
    "Galculator": ["--version"],
    "Htop": ["--version"],
    "AbiWord": ["--version"],
    "Gnumeric": ["--version"],
}

PATH_PATTERNS = {
    "legacy_usr_bin": re.compile(rb"(?<![A-Za-z0-9_./-])/usr/bin(?:/|\b)"),
    "legacy_usr_lib": re.compile(rb"(?<![A-Za-z0-9_./-])/usr/lib(?:/|\b)"),
    "legacy_usr_share": re.compile(rb"(?<![A-Za-z0-9_./-])/usr/share(?:/|\b)"),
    "legacy_etc": re.compile(rb"(?<![A-Za-z0-9_./-])/etc(?:/|\b)"),
    "legacy_var": re.compile(rb"(?<![A-Za-z0-9_./-])/var(?:/|\b)"),
    "legacy_bin": re.compile(rb"(?<![A-Za-z0-9_./-])/(?:s?bin)(?:/|\b)"),
}

GUI_FRONT_DOOR_PATTERNS = (
    "cannot open display",
    "Cannot open display",
    "Gtk-WARNING",
    "could not connect to display",
    "Missing display",
)


def root_join(root: Path, auzix_path: str) -> Path:
    return root / auzix_path.lstrip("/")


def load_receipts(root: Path) -> list[dict[str, Any]]:
    receipts = []
    for path in sorted((root / "System/PackageDB").glob("*.json")):
        try:
            receipt = json.loads(path.read_text())
        except Exception:
            continue
        receipt["_receipt_path"] = "/" + str(path.relative_to(root))
        receipts.append(receipt)
    return receipts


def is_elf(path: Path) -> bool:
    try:
        return path.read_bytes()[:4] == b"\x7fELF"
    except OSError:
        return False


def wrapper_text(path: Path) -> str:
    try:
        data = path.read_bytes()[:256 * 1024]
    except OSError:
        return ""
    if b"\0" in data[:4096]:
        return ""
    return data.decode("utf-8", "replace")


def extract_ld_library_path(wrapper: Path) -> str | None:
    text = wrapper_text(wrapper)
    for line in text.splitlines():
        if line.startswith("export LD_LIBRARY_PATH="):
            value = line.split("=", 1)[1].strip().strip('"')
            return value
    return None


def ldd_command(root: Path, command: Path, wrapper: Path | None) -> tuple[str, list[str]]:
    if is_elf(command):
        return str(command), []
    text = wrapper_text(command)
    candidates = re.findall(r'exec\s+"?\$\{runtime_loader\}"?.*?"\$\{program\}/([^"\s]+)"', text)
    if candidates:
        target = root_join(root, "/System/State/libreoffice/program/" + candidates[-1])
        if target.exists():
            return str(target), []
    roots = []
    if wrapper:
        roots.append(wrapper.parent.parent / "RootFS")
    roots.append(command.parent.parent / "RootFS")
    for base in roots:
        for rel in ("usr/bin/" + command.name, "usr/sbin/" + command.name, "bin/" + command.name, "sbin/" + command.name):
            candidate = base / rel
            if candidate.exists() and is_elf(candidate):
                return str(candidate), []
    return str(command), ["not-elf-or-target-not-found"]


def run(cmd: list[str], timeout: int = 12, env: dict[str, str] | None = None) -> tuple[int, str]:
    try:
        proc = subprocess.run(
            cmd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            env=env,
            check=False,
        )
        return proc.returncode, proc.stdout
    except subprocess.TimeoutExpired as exc:
        return 124, (exc.stdout or "") + "\nTIMEOUT\n"
    except Exception as exc:
        return 127, repr(exc)


def is_gui_front_door(output: str) -> bool:
    return any(pattern in output for pattern in GUI_FRONT_DOOR_PATTERNS)


def path_hits(path: Path) -> dict[str, int]:
    try:
        data = path.read_bytes()[:512 * 1024]
    except OSError:
        return {}
    hits = {}
    for name, pattern in PATH_PATTERNS.items():
        count = len(pattern.findall(data))
        if count:
            hits[name] = count
    return hits


def audit_package(root: Path, receipt: dict[str, Any]) -> dict[str, Any]:
    name = receipt.get("name") or "unknown"
    commands = receipt.get("commands") or []
    desktop_entries = receipt.get("desktop_entries") or []
    result: dict[str, Any] = {
        "name": name,
        "version": receipt.get("version"),
        "receipt": receipt.get("_receipt_path"),
        "commands": [],
        "desktop_entries": [],
        "status": "built",
        "failures": [],
    }

    for command in commands:
        full = root_join(root, command)
        command_result: dict[str, Any] = {
            "path": command,
            "exists": full.exists() or full.is_symlink(),
            "executable": os.access(full, os.X_OK),
            "ldd_missing": [],
            "path_hits": {},
            "smoke": None,
        }
        if not command_result["exists"]:
            result["failures"].append(f"missing command: {command}")
        elif not command_result["executable"]:
            result["failures"].append(f"non-executable command: {command}")
        else:
            target, ldd_notes = ldd_command(root, full, full)
            command_result["ldd_target"] = target
            command_result["ldd_notes"] = ldd_notes
            if not ldd_notes:
                rc, output = run(["ldd", target], timeout=10)
                command_result["ldd_rc"] = rc
                missing = [line.strip() for line in output.splitlines() if "not found" in line]
                command_result["ldd_missing"] = missing
                if missing:
                    result["failures"].append(f"ldd missing for {command}: {', '.join(missing[:4])}")
            command_result["path_hits"] = path_hits(full)
            smoke = SMOKE_ARGS.get(name)
            if smoke:
                rc, output = run([str(full), *smoke], timeout=12)
                command_result["smoke"] = {
                    "args": smoke,
                    "rc": rc,
                    "output_head": "\n".join(output.splitlines()[:8]),
                    "gui_front_door": is_gui_front_door(output),
                }
                if rc not in (0,) and not is_gui_front_door(output):
                    result["failures"].append(f"smoke failed for {command}: rc={rc}")
        result["commands"].append(command_result)

    for entry in desktop_entries:
        full = root_join(root, entry)
        entry_result = {"path": entry, "exists": full.exists() or full.is_symlink(), "exec": None, "categories": None}
        if entry_result["exists"]:
            text = wrapper_text(full)
            for line in text.splitlines():
                if line.startswith("Exec="):
                    entry_result["exec"] = line.split("=", 1)[1]
                if line.startswith("Categories="):
                    entry_result["categories"] = line.split("=", 1)[1]
        else:
            result["failures"].append(f"missing desktop entry: {entry}")
        result["desktop_entries"].append(entry_result)

    if not result["failures"] and result["commands"]:
        result["status"] = "launch-clean"
    elif not result["failures"]:
        result["status"] = "installable"
    else:
        result["status"] = "contract-failed"
    return result


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# AUZiX workstation watcher report",
        "",
        f"root: `{report['root']}`",
        "",
        "## Summary",
        "",
        f"- packages: {report['package_count']}",
        f"- launch-clean: {report['summary'].get('launch-clean', 0)}",
        f"- contract-failed: {report['summary'].get('contract-failed', 0)}",
        "",
        "## Failed packages",
        "",
    ]
    for pkg in report["packages"]:
        if pkg["status"] != "contract-failed":
            continue
        lines.append(f"### {pkg['name']} {pkg.get('version') or ''}".rstrip())
        for failure in pkg["failures"][:12]:
            lines.append(f"- {failure}")
        lines.append("")
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default="out/auzix-strict/AuzixRoot")
    parser.add_argument("--packages", nargs="*", default=None)
    parser.add_argument("--out", default="out/workstation-watch/workstation-watch.json")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    wanted = set(args.packages or [])
    receipts = load_receipts(root)
    if wanted:
        receipts = [receipt for receipt in receipts if receipt.get("name") in wanted]
    packages = [audit_package(root, receipt) for receipt in receipts]
    summary: dict[str, int] = {}
    for package in packages:
        summary[package["status"]] = summary.get(package["status"], 0) + 1
    report = {
        "format": "auzix-workstation-watch-v1",
        "root": str(root),
        "package_count": len(packages),
        "summary": summary,
        "packages": packages,
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    write_markdown(report, out.with_suffix(".md"))
    print(json.dumps({"report": str(out), "summary": summary}, sort_keys=True))
    return 1 if summary.get("contract-failed") else 0


if __name__ == "__main__":
    raise SystemExit(main())
