#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from auzix.model_review import query_ollama


def score(proposal: dict, oracle: dict) -> dict:
    rewrites = proposal["payload_rewrites"]
    serialized = json.dumps(proposal, sort_keys=True).casefold()
    new_values = [item.get("new") for item in rewrites if isinstance(item, dict)]
    checks = {}
    if "minimum_operations" in oracle:
        checks["minimum_operations"] = len(proposal["operations"]) >= oracle["minimum_operations"]
    if "minimum_payload_rewrites" in oracle:
        checks["minimum_payload_rewrites"] = len(rewrites) >= oracle["minimum_payload_rewrites"]
    if "maximum_payload_rewrites" in oracle:
        checks["maximum_payload_rewrites"] = len(rewrites) <= oracle["maximum_payload_rewrites"]
    if "required_new_values" in oracle:
        checks["required_new_values"] = all(value in new_values for value in oracle["required_new_values"])
    if "required_terms" in oracle:
        checks["required_terms"] = all(term.casefold() in serialized for term in oracle["required_terms"])
    if "required_discard_terms" in oracle:
        checks["required_discard_terms"] = all(term.casefold() in serialized for term in oracle["required_discard_terms"])
    if oracle.get("normal_remove_must_retain_state"):
        checks["normal_remove_retains_state"] = "retain" in serialized and "state" in serialized
    if "forbidden_terms" in oracle:
        checks["forbidden_terms"] = all(term.casefold() not in serialized for term in oracle["forbidden_terms"])
    if "exclusive_concepts" in oracle:
        contradictions = []
        action_text = json.dumps(
            {"operations": proposal["operations"], "scripts": proposal["scripts"]},
            sort_keys=True,
        ).casefold()
        discarded_text = json.dumps(proposal["discarded"], sort_keys=True).casefold()
        for concept in oracle["exclusive_concepts"]:
            terms = [term.casefold() for term in concept["terms"]]
            contradictions.append(
                any(term in action_text for term in terms)
                and any(term in discarded_text for term in terms)
            )
        checks["no_action_discard_contradiction"] = not any(contradictions)
    if "unresolved_must_not_be_scripted_terms" in oracle:
        action_text = json.dumps(
            {"operations": proposal["operations"], "scripts": proposal["scripts"]},
            sort_keys=True,
        ).casefold()
        risks_text = json.dumps(proposal["risks"], sort_keys=True).casefold()
        checks["unresolved_not_scripted"] = all(
            not (term.casefold() in risks_text and term.casefold() in action_text)
            for term in oracle["unresolved_must_not_be_scripted_terms"]
        )
    return {"passed": sum(checks.values()), "total": len(checks), "checks": checks}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", type=Path, default=Path("packaging/model-review-policy.json"))
    parser.add_argument("--fixture", type=Path, action="append", required=True)
    parser.add_argument("--model", action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    for fixture_path in args.fixture:
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        for model in args.model:
            safe_model = model.replace("/", "_").replace(":", "_")
            receipt_path = args.output / f"{fixture['fixture']}--{safe_model}.json"
            try:
                receipt = query_ollama(fixture_path, args.policy, model, output_path=receipt_path)
                receipt["score"] = score(receipt["proposal"], fixture["_oracle"])
                receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
                results.append({"fixture": fixture["fixture"], "model": model, **receipt["score"], "elapsed_seconds": receipt["elapsed_seconds"], "status": "completed"})
            except Exception as exc:
                results.append({"fixture": fixture["fixture"], "model": model, "status": "failed", "error": f"{type(exc).__name__}: {exc}"})
    report = {
        "format": "auzix-model-arena-v1",
        "created_at": datetime.now(ZoneInfo("America/Los_Angeles")).isoformat(),
        "results": results,
        "judges": {"human": "pending", "codex": "pending", "astra": "pending"},
        "promotion": "none-review-only",
    }
    (args.output / "arena.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    lines = ["# AUZiX Mega Monster Fight", "", "Best validated output wins; model output never promotes itself.", "", "| Fixture | Model | Score | Seconds | Status |", "|---|---|---:|---:|---|"]
    for item in results:
        score_text = f"{item.get('passed', 0)}/{item.get('total', 0)}"
        lines.append(f"| {item['fixture']} | {item['model']} | {score_text} | {item.get('elapsed_seconds', '-')} | {item['status']} |")
    lines.extend(["", "Model output is untrusted and cannot be promoted automatically.", ""])
    (args.output / "kanboard-note.md").write_text("\n".join(lines))
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
