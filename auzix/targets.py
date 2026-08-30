from __future__ import annotations

from typing import Any

from .contracts import ContractError, content_sha256, read_json
from .package_graph import compose_profile
from .paths import PACKAGING_ROOT, REPOSITORY_ROOT


def compose_target(name: str) -> dict[str, Any]:
    target_path = PACKAGING_ROOT / "targets" / f"{name}.json"
    target = read_json(target_path)
    if target.get("format") != "auzix-target-v1" or target.get("name") != name:
        raise ContractError(f"{target_path}: invalid target identity")
    profile_name = target.get("profile")
    if not isinstance(profile_name, str):
        raise ContractError(f"{target_path}: profile must be a string")
    activation_records = []
    seen_ids: set[str] = set()
    for relative in target.get("activation", []):
        if not isinstance(relative, str):
            raise ContractError(f"{target_path}: activation entries must be strings")
        path = PACKAGING_ROOT / relative
        fragment = read_json(path)
        if fragment.get("format") != "auzix-activation-fragment-v1":
            raise ContractError(f"{path}: invalid activation fragment format")
        fragment_id = fragment.get("id")
        if not isinstance(fragment_id, str) or fragment_id in seen_ids:
            raise ContractError(f"{path}: missing or duplicate activation id {fragment_id!r}")
        seen_ids.add(fragment_id)
        activation_records.append({"id": fragment_id, "path": str(path.relative_to(REPOSITORY_ROOT)), "sha256": content_sha256(fragment)})
    plan = {"format": "auzix-target-plan-v1", "target": name, "profile_lock": compose_profile(profile_name), "activation": activation_records, "media": target.get("media"), "gates": target.get("gates", []), "non_goals": target.get("non_goals", [])}
    plan["content_sha256"] = content_sha256(plan)
    return plan
