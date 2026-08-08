#!/usr/bin/env python3
import csv
import json
import sys
from collections import Counter
from pathlib import Path


def classify(row):
    status = row.get("status", "")
    install_rc = row.get("install_rc", "")
    exists = row.get("command_exists", "")
    run_rc = row.get("run_rc", "")
    output = row.get("run_output", "")

    if status == "absent":
        return "absent"
    if install_rc not in ("skip", "0"):
        if "package not found in repository" in output:
            return "missing-dependency"
        return "install-failed"
    if exists != "yes":
        return "missing-command"
    if run_rc == "0":
        return "worked"
    if "not found" in output and "package not found in repository" not in output:
        return "missing-runtime-library"
    if "GLIBC_" in output or "undefined symbol" in output or "version `" in output:
        return "abi-or-symbol-mismatch"
    if run_rc in ("124", "143"):
        return "timeout-or-gui-still-running"
    return "run-failed"


def main():
    if len(sys.argv) != 2:
        print("usage: summarize-auzix-shakedown.py SHAKEDOWN.tsv", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    rows = list(csv.DictReader(path.open(), delimiter="\t"))
    for row in rows:
        row["classification"] = classify(row)

    counts = Counter(row["classification"] for row in rows)
    failed = sum(count for key, count in counts.items() if key != "worked")

    print(json.dumps(
        {
            "format": "auzix-shakedown-summary-v1",
            "input": str(path),
            "total": len(rows),
            "worked": counts.get("worked", 0),
            "failed_or_not_ready": failed,
            "classifications": dict(sorted(counts.items())),
            "failed_packages": [
                {
                    "package": row["package"],
                    "classification": row["classification"],
                    "status": row["status"],
                    "install_rc": row["install_rc"],
                    "run_rc": row["run_rc"],
                    "output": row["run_output"],
                }
                for row in rows
                if row["classification"] != "worked"
            ],
        },
        indent=2,
        sort_keys=True,
    ))


if __name__ == "__main__":
    raise SystemExit(main())
