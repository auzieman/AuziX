#!/usr/bin/env python3
"""Merge reviewed archive inputs, retaining primary repairs over older intake."""
import json
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys


def prepare(primary, supplement, base_profile, extra_profile, destination, base_apks=None):
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
    # Explicit reviewed repairs override retained inputs only after verifying
    # their identity. Never infer a working replacement from a package name.
    for name, reviewed in extra.get("reviewed_archives", {}).items():
        spool = Path(reviewed["spool"])
        matches = [json.loads(p.read_text()) for p in (spool / "entries").glob("*.json")]
        matches = [record for record in matches if record["name"] == name]
        if len(matches) != 1:
            raise ValueError(f"expected one reviewed archive record: {name}")
        record = matches[0]
        filename = record["package"]
        if Path(filename).name != filename or record.get("version") != reviewed["version"]:
            raise ValueError(f"reviewed archive identity mismatch: {name}")
        digest = hashlib.sha256((spool / "packages" / filename).read_bytes()).hexdigest()
        if digest != reviewed["sha256"] or digest != record.get("sha256"):
            raise ValueError(f"reviewed archive hash mismatch: {name}")
        records[name], owners[name] = record, spool
    profile["name"] = "alpha-selected-runtime"
    profile["packages"] = list(dict.fromkeys(profile["packages"] + extra["packages"]))
    if not set(extra.get("reviewed_archives", {})).issubset(profile["packages"]):
        raise ValueError("reviewed archive is not requested by profile")
    for field in ("package_names", "external_providers", "dependency_additions"):
        profile.setdefault(field, {}).update(extra.get(field, {}))
    if base_apks is not None:
        # Older base APKs do not carry the donor source record. Recover their
        # canonical identity using the SAME name function as donor intake,
        # not a punctuation-stripping guess or another hand-maintained list.
        name_tool = Path(__file__).with_name("build-auzix-debian-intake-package.sh")
        providers = {}
        for archive in sorted(base_apks.glob("*.apk")):
            donor = archive.name.removesuffix(".apk").rsplit("-", 2)[0]
            if donor.startswith("auzix-"):
                continue
            canonical = subprocess.check_output(
                ["bash", str(name_tool), "--print-native-name", donor], text=True).strip()
            key = canonical.casefold()
            if key in providers and providers[key] != donor:
                raise ValueError(f"ambiguous base provider: {canonical}")
            providers[key] = donor
        identities = set(records)
        for record in records.values():
            identities.update(record.get("depends", []))
        for name in identities:
            if name.casefold() in providers:
                profile["external_providers"].setdefault(name, providers[name.casefold()])
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
    if len(sys.argv) not in (6, 7):
        raise SystemExit("usage: prepare-auzix-alpha-archives.py PRIMARY SUPPLEMENT BASE_PROFILE EXTRA_PROFILE DEST [BASE_APKS]")
    prepare(*(Path(argument) for argument in sys.argv[1:]))
