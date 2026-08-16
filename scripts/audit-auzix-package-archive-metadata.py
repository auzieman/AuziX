#!/usr/bin/env python3
"""Audit AUZiX package archives against the staged root metadata.

This catches the exact class of regression that bit the desktop: archive
creation that silently converts staged files to root/root or drops special
mode bits. AUZiX package extraction intentionally trusts the tar archive, so
the archive must preserve the package/staged-root ownership contract.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path


TAR_LINE = re.compile(
    r"^(?P<mode>[bcdlps-][rwxStTs-]{9})\s+"
    r"(?P<uid>\d+)/(?P<gid>\d+)\s+"
    r"\d+\s+"
    r"\d{4}-\d{2}-\d{2}\s+"
    r"\d{2}:\d{2}\s+"
    r"(?P<name>.+)$"
)


def parse_mode(mode_text: str) -> int:
    perms = 0
    triplets = mode_text[1:]
    mapping = ((stat.S_IRUSR, stat.S_IWUSR, stat.S_IXUSR),
               (stat.S_IRGRP, stat.S_IWGRP, stat.S_IXGRP),
               (stat.S_IROTH, stat.S_IWOTH, stat.S_IXOTH))
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
            yield ("parse-error", line, None)
            continue
        name = match.group("name")
        if " -> " in name and match.group("mode").startswith("l"):
            name = name.split(" -> ", 1)[0]
        yield (
            name,
            int(match.group("uid")),
            int(match.group("gid")),
            parse_mode(match.group("mode")),
            match.group("mode"),
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "auzix_root",
        nargs="?",
        default="out/auzix-strict/AuzixRoot",
        help="staged AUZiX root to compare against",
    )
    parser.add_argument(
        "--repo",
        default="artifacts/auzix/repo",
        help="AUZiX repository containing index.json and packages/",
    )
    parser.add_argument("--max-errors", type=int, default=50)
    parser.add_argument(
        "--forbid-builder-owned-system-paths",
        action="store_true",
        help=(
            "fail when the current user's uid/gid owns packaged system paths. "
            "Use this in the build pipeline to catch non-root staging leaks."
        ),
    )
    args = parser.parse_args()

    root = Path(args.auzix_root).resolve()
    repo = Path(args.repo).resolve()
    index_path = repo / "index.json"
    with index_path.open("r", encoding="utf-8") as handle:
        index = json.load(handle)

    errors: list[str] = []
    builder_uid = os.getuid()
    builder_gid = os.getgid()
    archives = 0
    entries = 0
    compared = 0

    for package in index.get("packages", []):
        archive_name = package.get("package")
        if not archive_name:
            continue
        archive = repo / "packages" / archive_name
        if not archive.exists():
            errors.append(f"missing archive referenced by index: {archive_name}")
            continue
        archives += 1
        for entry in tar_entries(archive):
            if entry[0] == "parse-error":
                errors.append(f"{archive_name}: cannot parse tar listing: {entry[1]}")
                continue
            rel_name, uid, gid, mode, mode_text = entry
            entries += 1
            staged = root / rel_name
            try:
                st = os.lstat(staged)
            except FileNotFoundError:
                continue
            compared += 1
            staged_mode = stat.S_IMODE(st.st_mode)
            mismatches = []
            if (st.st_uid, st.st_gid) != (uid, gid):
                mismatches.append(
                    f"owner staged={st.st_uid}:{st.st_gid} archive={uid}:{gid}"
                )
            if staged_mode != mode:
                mismatches.append(
                    f"mode staged={staged_mode:04o} archive={mode:04o} ({mode_text})"
                )
            if args.forbid_builder_owned_system_paths:
                system_path = not (
                    rel_name.startswith("Users/auzix/")
                    or rel_name == "Users/auzix"
                    or rel_name.startswith("run/user/1000/")
                    or rel_name == "run/user/1000"
                )
                builder_owned = (
                    builder_uid != 0
                    and (st.st_uid == builder_uid or st.st_gid == builder_gid)
                )
                if system_path and builder_owned:
                    mismatches.append(
                        "builder-owned system path "
                        f"staged={st.st_uid}:{st.st_gid} "
                        f"builder={builder_uid}:{builder_gid}"
                    )
            if mismatches:
                errors.append(f"{archive_name}:{rel_name}: " + "; ".join(mismatches))
                if len(errors) >= args.max_errors:
                    break
        if len(errors) >= args.max_errors:
            break

    print(
        f"archive metadata audit: archives={archives} entries={entries} "
        f"compared={compared} mismatches={len(errors)}"
    )
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
