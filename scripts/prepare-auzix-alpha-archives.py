#!/usr/bin/env python3
"""Merge reviewed archive inputs, retaining primary repairs over older intake."""
import json
from pathlib import Path
import shutil
import sys


def prepare(primary, supplement, base_profile, extra_profile, destination):
    records = {}
    owners = {}
    for spool in (supplement, primary):
        seen = set()
        for entry in sorted((spool / "entries").glob("*.json")):
            record = json.loads(entry.read_text())
            name = record["name"]
            if name in seen:
                raise ValueError(f"duplicate package identity in {spool}: {name}")
            seen.add(name)
            records[name] = record
            owners[name] = spool
    profile = json.loads(base_profile.read_text())
    extra = json.loads(extra_profile.read_text())
    profile["name"] = "alpha-selected-runtime"
    profile["packages"] = list(dict.fromkeys(profile["packages"] + extra["packages"]))
    for field in ("package_names", "external_providers", "dependency_additions"):
        profile.setdefault(field, {}).update(extra.get(field, {}))
    destination.mkdir(parents=True, exist_ok=False)
    (destination / "packages").mkdir()
    for name in profile["packages"]:
        record = records[name]
        filename = record["package"]
        if Path(filename).name != filename:
            raise ValueError(f"unsafe archive filename: {filename}")
        shutil.copyfile(owners[name] / "packages" / filename,
                        destination / "packages" / filename)
    # Unselected records supply upstream dependency identities, not payloads.
    (destination / "index.json").write_text(json.dumps(
        {"format": "auzix-repo-v1", "packages": list(records.values())}, indent=2))
    (destination / "profile.json").write_text(json.dumps(profile, indent=2))
    print(f"selected={len(profile['packages'])} provider_records={len(records)}")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        raise SystemExit("usage: prepare-auzix-alpha-archives.py PRIMARY SUPPLEMENT BASE_PROFILE EXTRA_PROFILE DEST")
    prepare(*(Path(argument) for argument in sys.argv[1:]))
