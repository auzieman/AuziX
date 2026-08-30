from __future__ import annotations

import shutil
from typing import Any

from .package_graph import load_packages
from .targets import compose_target


def target_preflight(name: str) -> dict[str, Any]:
    plan = compose_target(name)
    tools = {command: shutil.which(command) for command in ("python3", "fpm", "apk", "openssl")}
    selected = {item["name"] for item in plan["profile_lock"]["packages"]}
    external = [item["name"] for item in plan["profile_lock"]["packages"] if item["kind"] == "external-provider"]
    missing_producers = sorted(
        package_name
        for package_name, (_, package) in load_packages().items()
        if package_name in selected and not package["source"].get("legacy_entrypoint")
    )
    blockers = ["missing host tool: fpm"] if not tools["fpm"] else []
    if external:
        blockers.append("external providers not packaged: " + ", ".join(external))
    if missing_producers:
        blockers.append("payload producers not mapped: " + ", ".join(missing_producers))
    return {
        "format": "auzix-target-preflight-v1",
        "target": name,
        "target_plan_sha256": plan["content_sha256"],
        "tools": tools,
        "apk_provider": "host" if tools["apk"] else "verified-bootstrap-stage",
        "external_providers": external,
        "missing_package_producers": missing_producers,
        "blockers": blockers,
        "status": "passed" if not blockers else "blocked",
    }
