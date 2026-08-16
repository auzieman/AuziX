#!/usr/bin/env python3
"""Publish exactly one AUZiX desktop launcher per approved target.

This is the menu publication layer. It does not install packages and it does
not rebuild payloads. It normalizes/hides imported donor desktop entries, emits
canonical AUZiX launchers for targets whose command front door exists, runs a
bounded non-GUI probe when available, and writes a receipt.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
from pathlib import Path
from typing import Any


APP_DIR = "System/Compatibility/usr/share/applications"
LOG_GLOBS = [
    "Users/*/.e-log.log",
    "Users/*/.e/e.log",
    "Users/*/.cache/enlightenment/*.log",
    "System/Logs/**/*.log",
]


def root_join(root: Path, auzix_path: str) -> Path:
    return root / auzix_path.lstrip("/")


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def write_text_if_changed(path: Path, text: str) -> bool:
    if path.exists() and read_text(path) == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return True


def desktop_map(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in read_text(path).splitlines():
        if "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            data[key] = value
    return data


def set_key(lines: list[str], key: str, value: str) -> list[str]:
    out: list[str] = []
    seen = False
    for line in lines:
        if line.startswith(key + "="):
            if not seen:
                out.append(f"{key}={value}")
                seen = True
            continue
        out.append(line)
    if not seen:
        out.append(f"{key}={value}")
    return out


def hide_desktop(path: Path, reason: str) -> bool:
    lines = read_text(path).splitlines()
    if not lines:
        return False
    lines = set_key(lines, "NoDisplay", "true")
    lines = set_key(lines, "X-AUZiX-Launcher-State", reason)
    return write_text_if_changed(path, "\n".join(lines) + "\n")


def find_candidates(root: Path, target: dict[str, Any]) -> list[Path]:
    app_dir = root / APP_DIR
    if not app_dir.exists():
        return []
    wanted_files = set(target.get("desktop_files", []))
    wanted_names = set(target.get("desktop_names", []))
    candidates: list[Path] = []
    for path in sorted(app_dir.glob("*.desktop")):
        data = desktop_map(path)
        if path.name in wanted_files or data.get("Name") in wanted_names:
            candidates.append(path)
    return candidates


def command_exists(root: Path, command: str) -> bool:
    path = root_join(root, command)
    return path.exists() and os.access(path, os.X_OK)


def run_probe(root: Path, command: str, args: list[str], timeout: int) -> dict[str, Any]:
    full = root_join(root, command)
    if not args:
        return {"status": "skipped", "reason": "no-probe"}
    if root != Path("/"):
        return {"status": "skipped", "reason": "offline-root"}
    env = os.environ.copy()
    env.setdefault("HOME", "/Users/auzix")
    env.setdefault("USER", "auzix")
    env.setdefault("LOGNAME", "auzix")
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/1000")
    try:
        proc = subprocess.run(
            [str(full), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            env=env,
            check=False,
        )
        return {
            "status": "pass" if proc.returncode == 0 or "Cannot open display" in proc.stdout or "cannot open display" in proc.stdout else "fail",
            "rc": proc.returncode,
            "output_head": "\n".join(proc.stdout.splitlines()[:12]),
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "status": "timeout",
            "rc": 124,
            "output_head": "\n".join(((exc.stdout or "") + "\nTIMEOUT").splitlines()[:12]),
        }
    except Exception as exc:
        return {"status": "error", "error": repr(exc)}


def canonical_desktop(target: dict[str, Any], state: str, hidden: bool) -> str:
    categories = ";".join(target.get("categories", ["Utility"])) + ";"
    command = target["command"]
    name = target["name"]
    icon = target.get("icon", "application-x-executable")
    terminal = "false"
    if "Terminal" in target:
        terminal = "true" if target["Terminal"] else "false"
    lines = [
        "[Desktop Entry]",
        "Type=Application",
        f"Name={name}",
        f"Exec={command} %U",
        f"Icon={icon}",
        f"Terminal={terminal}",
        f"Categories={categories}",
        f"NoDisplay={'true' if hidden else 'false'}",
        f"X-AUZiX-Launcher-State={state}",
        f"X-AUZiX-Launcher-Id={target['id']}",
    ]
    return "\n".join(lines) + "\n"


def collect_log_tails(root: Path) -> list[dict[str, str]]:
    logs: list[dict[str, str]] = []
    for pattern in LOG_GLOBS:
        for path in sorted(root.glob(pattern)):
            if path.is_file():
                text = read_text(path)
                if text:
                    logs.append({
                        "path": "/" + str(path.relative_to(root)),
                        "tail": "\n".join(text.splitlines()[-80:]),
                    })
    return logs[-12:]


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# AUZiX first-wave desktop launcher publish report",
        "",
        f"- root: `{report['root']}`",
        f"- profile: `{report.get('profile')}`",
        f"- apply: `{report['apply']}`",
        "",
        "## Targets",
        "",
    ]
    for item in report["targets"]:
        lines.extend([
            f"### {item['name']} `{item['id']}`",
            "",
            f"- state: `{item['state']}`",
            f"- promoted: `{item['promoted']}`",
            f"- command: `{item['command']}`",
            f"- command_exists: `{item['command_exists']}`",
            f"- canonical_desktop: `{item['canonical_desktop']}`",
        ])
        if item["candidate_desktops"]:
            lines.append(f"- candidates: `{', '.join(item['candidate_desktops'])}`")
        probe = item.get("probe") or {}
        lines.append(f"- probe_status: `{probe.get('status')}`")
        if probe.get("rc") is not None:
            lines.append(f"- probe_rc: `{probe.get('rc')}`")
        if probe.get("output_head"):
            lines.extend(["", "```text", probe["output_head"], "```"])
        if probe.get("error"):
            lines.extend(["", "```text", probe["error"], "```"])
        lines.append("")

    lines.extend(["## Embedded Enlightenment/session log tails", ""])
    logs = report.get("enlightenment_log_tails") or []
    if not logs:
        lines.append("No Enlightenment/session logs were found in the scanned locations.")
        lines.append("")
    for log in logs:
        lines.extend([
            f"### `{log['path']}`",
            "",
            "```text",
            log.get("tail") or "(empty)",
            "```",
            "",
        ])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def refresh_caches(root: Path) -> list[str]:
    actions: list[str] = []
    if root != Path("/"):
        return actions
    commands = [
        ["/Programs/DesktopFileUtils/current/Commands/update-desktop-database", "/System/Compatibility/usr/share/applications"],
        ["/Programs/SharedMimeInfo/current/Commands/update-mime-database", "/System/Compatibility/usr/share/mime"],
    ]
    for cmd in commands:
        if Path(cmd[0]).exists():
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            actions.append(" ".join(cmd))
    if Path("/Programs/BusyBox/current/Commands/busybox").exists() and Path("/Users/auzix/.e/e/applications/menu/all").exists():
        # Keep this bounded: cache refresh is handled by E/Efreet as user session runs.
        actions.append("efreet-cache-refresh-deferred-to-session")
    return actions


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default="/")
    parser.add_argument("--profile", default="packages/desktop-first-wave-launchers.profile.json")
    parser.add_argument("--out", default=None)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--probe-timeout", type=int, default=12)
    parser.add_argument("--promote-on-missing-probe", action="store_true")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    profile = json.loads(Path(args.profile).read_text())
    app_dir = root / APP_DIR
    app_dir.mkdir(parents=True, exist_ok=True)

    report: dict[str, Any] = {
        "format": "auzix-desktop-launcher-publish-v1",
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "root": str(root),
        "profile": profile.get("name"),
        "apply": args.apply,
        "targets": [],
        "cache_actions": [],
        "enlightenment_log_tails": [],
    }

    all_target_candidate_paths: set[Path] = set()
    for target in profile["targets"]:
        candidates = find_candidates(root, target)
        all_target_candidate_paths.update(candidates)
        command_ok = command_exists(root, target["command"])
        probe = {"status": "skipped", "reason": "missing-command"}
        if command_ok:
            probe = run_probe(root, target["command"], target.get("probe", []), args.probe_timeout)
        promote = command_ok and (probe.get("status") == "pass" or (args.promote_on_missing_probe and probe.get("status") == "skipped"))
        state = "desktop-visible" if promote else ("command-present-probe-failed" if command_ok else "missing-command")
        hidden = not promote
        canonical_name = f"auzix-{target['id']}.desktop"
        canonical_path = app_dir / canonical_name
        changed = False

        if args.apply:
            for path in candidates:
                if path != canonical_path:
                    changed = hide_desktop(path, f"quarantined-duplicate-of-{target['id']}") or changed
            changed = write_text_if_changed(canonical_path, canonical_desktop(target, state, hidden)) or changed

        report["targets"].append({
            "id": target["id"],
            "name": target["name"],
            "command": target["command"],
            "command_exists": command_ok,
            "probe": probe,
            "promoted": promote,
            "canonical_desktop": "/" + str(canonical_path.relative_to(root)),
            "candidate_desktops": ["/" + str(path.relative_to(root)) for path in candidates],
            "changed": changed,
            "state": state,
        })

    if args.apply:
        report["cache_actions"] = refresh_caches(root)
    report["enlightenment_log_tails"] = collect_log_tails(root)

    out = Path(args.out) if args.out else root_join(root, "/System/State/reports/desktop-launcher-publish-first-wave.json")
    if root != Path("/") and not args.out:
        out = Path("out/workstation-watch/desktop-launcher-publish-first-wave.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(report, out.with_suffix(".md"))
    print(json.dumps({
        "report": str(out),
        "markdown": str(out.with_suffix(".md")),
        "promoted": sum(1 for item in report["targets"] if item["promoted"]),
        "hidden_or_failed": sum(1 for item in report["targets"] if not item["promoted"]),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
