from __future__ import annotations

import ipaddress
import json
import socket
import urllib.parse
import urllib.request
import time as monotonic_time
from datetime import datetime, time
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .contracts import ContractError


REQUIRED_PROPOSAL_KEYS = {
    "operations", "scripts", "payload_rewrites", "discarded", "risks"
}


def _private_endpoint(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "http" or not parsed.hostname:
        raise ContractError("model endpoint must be a private HTTP endpoint")
    try:
        addresses = {item[4][0] for item in socket.getaddrinfo(parsed.hostname, parsed.port or 80)}
    except socket.gaierror as exc:
        raise ContractError(f"model endpoint does not resolve: {parsed.hostname}") from exc
    if not addresses or any(not ipaddress.ip_address(address).is_private for address in addresses):
        raise ContractError("model endpoint must resolve only to loopback/private addresses")


def _before_cutoff(cutoff: str, timezone: str, now: datetime | None = None) -> None:
    try:
        hour, minute = (int(part) for part in cutoff.split(":"))
        cutoff_time = time(hour, minute)
        zone = ZoneInfo(timezone)
    except (TypeError, ValueError, ZoneInfoNotFoundError) as exc:
        raise ContractError("invalid model review cutoff or timezone") from exc
    current = now.astimezone(zone) if now else datetime.now(zone)
    if current.time() >= cutoff_time:
        raise ContractError(f"model review cutoff reached: {cutoff} {timezone}")


def validate_proposal(proposal: Any) -> dict[str, Any]:
    if not isinstance(proposal, dict) or set(proposal) != REQUIRED_PROPOSAL_KEYS:
        raise ContractError("model proposal has an invalid top-level schema")
    for key in REQUIRED_PROPOSAL_KEYS:
        if not isinstance(proposal[key], list):
            raise ContractError(f"model proposal {key} must be an array")
    for rewrite in proposal["payload_rewrites"]:
        if not isinstance(rewrite, dict) or set(rewrite) != {"path", "old", "new", "expected"}:
            raise ContractError("model payload rewrite must contain path, old, new, expected")
        if not isinstance(rewrite["expected"], int) or rewrite["expected"] < 1:
            raise ContractError("model payload rewrite expected must be a positive integer")
    return proposal


def query_ollama(
    evidence_path: Path,
    policy_path: Path,
    model: str,
    *,
    output_path: Path | None = None,
) -> dict[str, Any]:
    policy = json.loads(policy_path.read_text(encoding="utf-8"))
    endpoint = policy["endpoint"].rstrip("/")
    _private_endpoint(endpoint)
    _before_cutoff(policy["cutoff"], policy["timezone"])
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    evidence.pop("_oracle", None)
    prompt = policy["prompt"] + "\nEVIDENCE:\n" + json.dumps(evidence, sort_keys=True)
    request = urllib.request.Request(
        endpoint + "/api/generate",
        data=json.dumps({
            "model": model,
            "stream": False,
            "format": "json",
            "think": False,
            "prompt": prompt,
            "options": {"temperature": 0, "num_predict": policy["max_output_tokens"]},
        }).encode(),
        headers={"Content-Type": "application/json"},
    )
    started = monotonic_time.monotonic()
    with urllib.request.urlopen(request, timeout=policy["timeout_seconds"]) as response:
        envelope = json.loads(response.read())
    elapsed = round(monotonic_time.monotonic() - started, 3)
    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        raw_path = output_path.with_suffix(".raw.json")
        raw_path.write_text(json.dumps(envelope, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    raw_response = envelope.get("response", "")
    if not isinstance(raw_response, str) or not raw_response.strip():
        raise ContractError("model returned no final response")
    proposal = validate_proposal(json.loads(raw_response))
    result = {
        "format": "auzix-model-review-v1",
        "model": model,
        "evidence": str(evidence_path),
        "proposal": proposal,
        "elapsed_seconds": elapsed,
        "promotion": "prohibited-model-output-review-only",
    }
    if output_path:
        output_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return result
