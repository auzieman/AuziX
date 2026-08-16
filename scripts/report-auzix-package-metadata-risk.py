#!/usr/bin/env python3
"""Report AUZiX package metadata risk and spot-fix burden.

This is the narrative companion to audit-auzix-package-archive-metadata.py.
The audit answers "does the archive match the staged root?"  This report also
answers "would this root have produced the cursed desktop class of bugs?"

It intentionally calls out builder-owned system paths, missing special bits,
and archive-vs-stage drift because those are the exact failures that make
LightDM, Xorg, sudo, DBus, efreet, and Enlightenment look randomly haunted.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import subprocess
from collections import Counter, defaultdict
from pathlib import Path


TAR_LINE = re.compile(
    r"^(?P<mode>[bcdlps-][rwxStTs-]{9})\s+"
    r"(?P<uid>\d+)/(?P<gid>\d+)\s+"
    r"\d+\s+"
    r"\d{4}-\d{2}-\d{2}\s+"
    r"\d{2}:\d{2}\s+"
    r"(?P<name>.+)$"
)

SENSITIVE_PATTERNS = (
    "sudo",
    "Xorg.wrap",
    "enlightenment_system",
    "enlightenment_ckpasswd",
    "lightdm",
    "dbus",
    "polkit",
    "udev",
    "efreet",
    "flatpak",
    "system-helper",
    "sudoers",
)


def parse_mode(mode_text: str) -> int:
    perms = 0
    triplets = mode_text[1:]
    mapping = (
        (stat.S_IRUSR, stat.S_IWUSR, stat.S_IXUSR),
        (stat.S_IRGRP, stat.S_IWGRP, stat.S_IXGRP),
        (stat.S_IROTH, stat.S_IWOTH, stat.S_IXOTH),
    )
    for offset, bits in enumerate(mapping):
        r, w, x = triplets[offset * 3: offset * 3 + 3]
        if r == "r":
            perms |= bits[0]
        if w == "w":
            perms |= bits[1]
        if x in ("x", "s", "t"):
            perms |= bits[2]
        if x in ("s", "S") and offset == 0:
            perms |= stat.S_ISUID
        if x in ("s", "S") and offset == 1:
            perms |= stat.S_ISGID
        if x in ("t", "T") and offset == 2:
            perms |= stat.S_ISVTX
    return perms


def tar_entries(archive: Path):
    proc = subprocess.run(
        ["tar", "--numeric-owner", "-tvf", str(archive)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    for line in proc.stdout.splitlines():
        match = TAR_LINE.match(line)
        if not match:
            continue
        name = match.group("name")
        if " -> " in name and match.group("mode").startswith("l"):
            name = name.split(" -> ", 1)[0]
        yield {
            "name": name,
            "uid": int(match.group("uid")),
            "gid": int(match.group("gid")),
            "mode": parse_mode(match.group("mode")),
            "mode_text": match.group("mode"),
        }


def is_user_state(path: str) -> bool:
    return (
        path == "Users/auzix"
        or path.startswith("Users/auzix/")
        or path == "run/user/1000"
        or path.startswith("run/user/1000/")
    )


def is_sensitive(path: str) -> bool:
    lower = path.lower()
    return any(pattern.lower() in lower for pattern in SENSITIVE_PATTERNS)


def sample(items: list[dict], limit: int) -> list[dict]:
    return items[:limit]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "auzix_root",
        nargs="?",
        default="out/auzix-strict/AuzixRoot",
        help="staged AUZiX root to inspect",
    )
    parser.add_argument("--repo", default="artifacts/auzix/repo")
    parser.add_argument(
        "--suspicious-owner",
        default="1000:1000",
        help="uid:gid that should not own packaged system paths; use the laptop/builder uid",
    )
    parser.add_argument("--json-out")
    parser.add_argument("--md-out")
    parser.add_argument("--sample-limit", type=int, default=30)
    args = parser.parse_args()

    suspicious_uid, suspicious_gid = [int(part) for part in args.suspicious_owner.split(":", 1)]
    root = Path(args.auzix_root).resolve()
    repo = Path(args.repo).resolve()
    index = json.loads((repo / "index.json").read_text(encoding="utf-8"))

    totals = Counter()
    per_package = defaultdict(Counter)
    archive_mismatches: list[dict] = []
    suspicious_system_owner: list[dict] = []
    special_modes: list[dict] = []
    sensitive_entries: list[dict] = []

    for package in index.get("packages", []):
        archive_name = package.get("package")
        if not archive_name:
            continue
        archive = repo / "packages" / archive_name
        if not archive.exists():
            archive_mismatches.append({"package": archive_name, "path": "<archive>", "issue": "missing archive"})
            continue
        totals["archives"] += 1
        for entry in tar_entries(archive):
            totals["entries"] += 1
            rel = entry["name"]
            staged = root / rel
            try:
                st = os.lstat(staged)
            except FileNotFoundError:
                continue
            totals["compared"] += 1
            staged_mode = stat.S_IMODE(st.st_mode)
            pkg_counter = per_package[archive_name]
            pkg_counter["entries"] += 1

            if (st.st_uid, st.st_gid) != (entry["uid"], entry["gid"]) or staged_mode != entry["mode"]:
                issue = {
                    "package": archive_name,
                    "path": rel,
                    "staged_owner": f"{st.st_uid}:{st.st_gid}",
                    "archive_owner": f"{entry['uid']}:{entry['gid']}",
                    "staged_mode": f"{staged_mode:04o}",
                    "archive_mode": f"{entry['mode']:04o}",
                }
                archive_mismatches.append(issue)
                totals["archive_mismatches"] += 1
                pkg_counter["archive_mismatches"] += 1

            if not is_user_state(rel) and (st.st_uid == suspicious_uid or st.st_gid == suspicious_gid):
                issue = {
                    "package": archive_name,
                    "path": rel,
                    "owner": f"{st.st_uid}:{st.st_gid}",
                    "mode": f"{staged_mode:04o}",
                }
                suspicious_system_owner.append(issue)
                totals["suspicious_system_owner"] += 1
                pkg_counter["suspicious_system_owner"] += 1

            if staged_mode & (stat.S_ISUID | stat.S_ISGID | stat.S_ISVTX):
                issue = {
                    "package": archive_name,
                    "path": rel,
                    "owner": f"{st.st_uid}:{st.st_gid}",
                    "mode": f"{staged_mode:04o}",
                }
                special_modes.append(issue)
                totals["special_modes"] += 1
                pkg_counter["special_modes"] += 1

            if is_sensitive(rel):
                sensitive_entries.append(
                    {
                        "package": archive_name,
                        "path": rel,
                        "owner": f"{st.st_uid}:{st.st_gid}",
                        "mode": f"{staged_mode:04o}",
                    }
                )
                totals["sensitive_entries"] += 1
                pkg_counter["sensitive_entries"] += 1

    spot_fix_commands = (
        totals["archive_mismatches"]
        + totals["suspicious_system_owner"]
        + totals["special_modes"]
    )
    if spot_fix_commands == 0:
        burden = "low"
    elif spot_fix_commands < 25:
        burden = "medium"
    else:
        burden = "high"

    report = {
        "format": "auzix-package-metadata-risk-v1",
        "root": str(root),
        "repo": str(repo),
        "suspicious_owner": f"{suspicious_uid}:{suspicious_gid}",
        "totals": dict(totals),
        "spot_fix_burden": {
            "classification": burden,
            "estimated_manual_actions": spot_fix_commands,
            "note": (
                "Each mismatch or suspicious owner usually implies a chmod/chown/"
                "hook decision. High counts mean package rebuild/repack is safer "
                "than VM spot repair."
            ),
        },
        "top_packages": [
            {"package": pkg, **dict(counts)}
            for pkg, counts in sorted(
                per_package.items(),
                key=lambda item: sum(v for k, v in item[1].items() if k != "entries"),
                reverse=True,
            )[:20]
        ],
        "samples": {
            "archive_mismatches": sample(archive_mismatches, args.sample_limit),
            "suspicious_system_owner": sample(suspicious_system_owner, args.sample_limit),
            "special_modes": sample(special_modes, args.sample_limit),
            "sensitive_entries": sample(sensitive_entries, args.sample_limit),
        },
    }

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    md_lines = [
        "# AUZiX package metadata risk report",
        "",
        f"- root: `{root}`",
        f"- repo: `{repo}`",
        f"- suspicious owner: `{suspicious_uid}:{suspicious_gid}`",
        f"- archives: `{totals['archives']}`",
        f"- entries compared: `{totals['compared']}`",
        f"- archive/staged mismatches: `{totals['archive_mismatches']}`",
        f"- suspicious system-owner paths: `{totals['suspicious_system_owner']}`",
        f"- special-mode paths: `{totals['special_modes']}`",
        f"- sensitive desktop/service entries observed: `{totals['sensitive_entries']}`",
        f"- spot-fix burden: `{burden}` (`{spot_fix_commands}` estimated manual chmod/chown/hook decisions)",
        "",
        "## Why this matters",
        "",
        "If this report shows many suspicious system-owner paths or metadata mismatches,",
        "the correct fix is package rebuild/repack with the package install logic intact.",
        "Spot-fixing a live VM would require auditing every helper, service, socket, cache,",
        "desktop entry, and generated state path by hand.",
        "",
        "## Top packages by metadata risk",
        "",
    ]
    for pkg in report["top_packages"][:10]:
        md_lines.append(
            f"- `{pkg['package']}`: suspicious={pkg.get('suspicious_system_owner', 0)}, "
            f"mismatches={pkg.get('archive_mismatches', 0)}, "
            f"special={pkg.get('special_modes', 0)}, sensitive={pkg.get('sensitive_entries', 0)}"
        )
    md_lines.extend(["", "## Samples", ""])
    for section, items in report["samples"].items():
        md_lines.extend([f"### {section}", ""])
        if not items:
            md_lines.append("- none")
        else:
            for item in items[: args.sample_limit]:
                md_lines.append(f"- `{item.get('package')}` `{item.get('path')}` {item}")
        md_lines.append("")
    md_text = "\n".join(md_lines)

    if args.md_out:
        Path(args.md_out).write_text(md_text + "\n", encoding="utf-8")
    print(md_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
