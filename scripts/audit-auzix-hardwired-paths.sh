#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPORT_DIR="${ROOT_DIR}/out/package-bot"
REPORT_JSON="${2:-${REPORT_DIR}/hardwired-paths.report.json}"
REPORT_TEXT="${REPORT_JSON%.json}.txt"

mkdir -p "$(dirname "${REPORT_JSON}")"

if [[ ! -d "${AUZIX_ROOT}/Programs" ]]; then
  printf 'AUZiX root missing Programs directory: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

python3 - "$AUZIX_ROOT" "$REPORT_JSON" "$REPORT_TEXT" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
report_json = Path(sys.argv[2])
report_text = Path(sys.argv[3])

patterns = [
    ("legacy_usr_lib", re.compile(rb"(?<![A-Za-z0-9_./-])/usr/lib(?:/|\\b)")),
    ("legacy_usr_bin", re.compile(rb"(?<![A-Za-z0-9_./-])/usr/bin(?:/|\\b)")),
    ("legacy_usr_share", re.compile(rb"(?<![A-Za-z0-9_./-])/usr/share(?:/|\\b)")),
    ("legacy_etc", re.compile(rb"(?<![A-Za-z0-9_./-])/etc(?:/|\\b)")),
    ("legacy_var", re.compile(rb"(?<![A-Za-z0-9_./-])/var(?:/|\\b)")),
    ("legacy_lib", re.compile(rb"(?<![A-Za-z0-9_./-])/lib(?:64)?(?:/|\\b)")),
    ("legacy_bin", re.compile(rb"(?<![A-Za-z0-9_./-])/(?:s?bin)(?:/|\\b)")),
    ("runtime_run", re.compile(rb"(?<![A-Za-z0-9_./-])/run(?:/|\\b)")),
]

allow_text_suffixes = {
    ".sh", ".py", ".pl", ".rb", ".lua", ".desktop", ".service", ".conf",
    ".ini", ".rc", ".xml", ".xcu", ".xcd", ".json", ".txt", ".pc",
    ".cmake", ".la", ".in", ".policy", ".rules", ".schemas", ".list",
}

def looks_text(path: Path) -> bool:
    if path.suffix in allow_text_suffixes:
        return True
    try:
        data = path.read_bytes()[:4096]
    except OSError:
        return False
    if b"\0" in data:
        return False
    if not data:
        return True
    printable = sum(1 for b in data if b in b"\n\r\t" or 32 <= b <= 126)
    return printable / len(data) > 0.90

def package_from_path(path: Path):
    rel = path.relative_to(root)
    parts = rel.parts
    if len(parts) >= 3 and parts[0] == "Programs":
        return parts[1], parts[2], "/".join(parts[3:])
    return None, None, str(rel)

def classify_payload(payload_path: str, executable: bool) -> str:
    if "/usr/share/doc/" in payload_path or "/usr/share/bug/" in payload_path:
        return "documentation"
    if payload_path.endswith(".desktop"):
        return "desktop-entry"
    if "/dbus-1/services/" in payload_path or payload_path.endswith(".service"):
        return "service-activation"
    if "/glib-2.0/schemas/" in payload_path or payload_path.endswith((".xcu", ".xcd", ".schemas")):
        return "schema-config"
    if "/etc/" in payload_path or payload_path.endswith((".conf", ".ini", ".rc", ".policy", ".rules")):
        return "configuration"
    if executable or "/usr/bin/" in payload_path or "/usr/libexec/" in payload_path:
        return "executable-script"
    if "/usr/lib/" in payload_path:
        return "library-config"
    return "payload-text"

severity_order = {
    "executable-script": 0,
    "service-activation": 1,
    "desktop-entry": 2,
    "configuration": 3,
    "schema-config": 4,
    "library-config": 5,
    "payload-text": 6,
    "documentation": 9,
}

findings = []
totals = {name: 0 for name, _ in patterns}
package_totals = {}
actionable_package_totals = {}
scanned_files = 0

for program_dir in sorted((root / "Programs").glob("*/*")):
    rootfs = program_dir / "RootFS"
    if not rootfs.is_dir():
        continue
    for path in rootfs.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        if path.stat().st_size > 2 * 1024 * 1024:
            continue
        if not looks_text(path):
            continue
        scanned_files += 1
        try:
            data = path.read_bytes()
        except OSError:
            continue
        hits = []
        for name, pattern in patterns:
            count = len(pattern.findall(data))
            if count:
                hits.append({"pattern": name, "count": count})
                totals[name] += count
        if not hits:
            continue
        package, version, rel_payload = package_from_path(path)
        payload_class = classify_payload(rel_payload, os.access(path, os.X_OK))
        actionable = payload_class != "documentation"
        key = f"{package}@{version}"
        package_totals.setdefault(key, 0)
        package_totals[key] += sum(hit["count"] for hit in hits)
        if actionable:
            actionable_package_totals.setdefault(key, 0)
            actionable_package_totals[key] += sum(hit["count"] for hit in hits)
        findings.append({
            "package": package,
            "version": version,
            "path": "/" + str(path.relative_to(root)),
            "payload_path": rel_payload,
            "payload_class": payload_class,
            "actionable": actionable,
            "hits": hits,
        })

priority_packages = [
    {"package": key.split("@", 1)[0], "version": key.split("@", 1)[1], "hits": count}
    for key, count in sorted(package_totals.items(), key=lambda item: (-item[1], item[0]))
]
actionable_priority_packages = [
    {"package": key.split("@", 1)[0], "version": key.split("@", 1)[1], "hits": count}
    for key, count in sorted(actionable_package_totals.items(), key=lambda item: (-item[1], item[0]))
]
findings.sort(key=lambda item: (
    severity_order.get(item["payload_class"], 8),
    item["package"] or "",
    item["payload_path"],
))

report = {
    "format": "auzix-hardwired-path-audit-v1",
    "root": str(root),
    "scanned_text_files": scanned_files,
    "finding_count": len(findings),
    "actionable_finding_count": sum(1 for item in findings if item["actionable"]),
    "totals": totals,
    "actionable_priority_packages": actionable_priority_packages[:50],
    "priority_packages": priority_packages[:50],
    "findings": findings,
    "ollama_prompt_hint": (
        "Classify each finding as build-variable/configurable, wrapper-fixable, "
        "sed-patchable payload text, service/session dependency, or acceptable runtime "
        "kernel path. Prefer AUZiX paths under /Programs, /System/Settings, /System/State, "
        "and /Services. Do not propose broad /usr compatibility links unless no narrower "
        "package-owned fix exists."
    ),
}

report_json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

with report_text.open("w") as fh:
    fh.write(f"AUZiX hardwired path audit\n")
    fh.write(f"root: {root}\n")
    fh.write(f"scanned_text_files: {scanned_files}\n")
    fh.write(f"finding_count: {len(findings)}\n")
    fh.write(f"actionable_finding_count: {sum(1 for item in findings if item['actionable'])}\n")
    fh.write("totals:\n")
    for name, count in sorted(totals.items()):
        fh.write(f"  {name}: {count}\n")
    fh.write("actionable_priority_packages:\n")
    for item in actionable_priority_packages[:30]:
        fh.write(f"  {item['package']} {item['version']}: {item['hits']}\n")
    fh.write("sample_findings:\n")
    for item in findings[:200]:
        hit_text = ", ".join(f"{h['pattern']}={h['count']}" for h in item["hits"])
        fh.write(f"  {item['package']} {item['version']} [{item['payload_class']}] {item['payload_path']} :: {hit_text}\n")

print(json.dumps({
    "report": str(report_json),
    "text": str(report_text),
    "finding_count": len(findings),
    "actionable_finding_count": sum(1 for item in findings if item["actionable"]),
    "actionable_priority_packages": actionable_priority_packages[:10],
}, sort_keys=True))
PY
