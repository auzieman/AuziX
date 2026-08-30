from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any


DONOR_PROTOCOL = re.compile(
    r"\b(?:dpkg(?:-[a-z0-9-]+)?|deb-systemd-(?:helper|invoke)|debconf|ucf|ucfr|"
    r"invoke-rc\.d|update-rc\.d|systemctl|runit-helper)\b"
)
PORTABLE_EFFECT = re.compile(
    r"(?:^|[;&|]\s*)(?:command\s+)?"
    r"(?P<command>mkdir|chmod|chown|chgrp|mv|ln|rm|touch|install|cp|cat|sed|awk|find|printf|echo)\b"
)
SHELL_CONTROL = re.compile(
    r"^(?:if|then|elif|else|fi|case|esac|for|while|until|do|done|\{|\}|[A-Za-z_][A-Za-z0-9_]*\(\))"
)

EFFECT_PATTERNS = (
    (
        "package-payload-query",
        "donor-protocol",
        re.compile(r"\bdpkg\s+(?:-L|--listfiles)\s+(?P<target>[^\s|;]+)"),
    ),
    (
        "python-bytecode-compile",
        "portable-intent",
        re.compile(
            r"(?<![A-Za-z0-9._/-])(?P<target>/[^\s;]*python[0-9.]+)\b"
            r"[^\n;]*\bpy_compile\.py\b"
        ),
    ),
    (
        "runtime-hook-dispatch",
        "donor-protocol",
        re.compile(r"\bfor\s+\w+\s+in\s+(?P<target>/\S*/runtime\.d/\*\.rt(?:install|remove))"),
    ),
    (
        "binfmt-registration",
        "deferred-boot-action",
        re.compile(r"(?:^|[;&|]\s*)update-binfmts\s+(?P<target>[^\n]*)"),
    ),
    (
        "filesystem-effect",
        "portable-intent",
        re.compile(
            r"(?:^|[;&|]\s*)(?P<command>mkdir|chmod|chown|chgrp|mv|ln|rm|rmdir|touch|install|cp)"
            r"\s+(?P<arguments>[^\n]*)"
        ),
    ),
)


def _logical_shell_lines(text: str) -> list[tuple[int, int, str]]:
    """Join explicit shell continuations while retaining exact evidence ranges."""
    physical = text.splitlines()
    logical: list[tuple[int, int, str]] = []
    start = 1
    buffered: list[str] = []
    for number, raw in enumerate(physical, 1):
        if not buffered:
            start = number
        buffered.append(raw)
        if raw.rstrip().endswith("\\"):
            continue
        logical.append((start, number, "\n".join(buffered)))
        buffered = []
    if buffered:
        logical.append((start, len(physical), "\n".join(buffered)))
    return logical


def grok_donor_script(source_path: str, text: str) -> list[dict[str, Any]]:
    """Extract review candidates without treating recognition as authorization."""
    effects: list[dict[str, Any]] = []
    functions = {
        match.group("name")
        for match in re.finditer(
            r"(?m)^\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)\s*(?:\{|$)", text
        )
    }
    for start, end, logical in _logical_shell_lines(text):
        flattened = re.sub(r"\\\n\s*", " ", logical).strip()
        if not flattened or flattened.startswith("#"):
            continue
        for effect_type, disposition, pattern in EFFECT_PATTERNS:
            for match in pattern.finditer(flattened):
                effect: dict[str, Any] = {
                    "type": effect_type,
                    "disposition": disposition,
                    "evidence": {
                        "source": source_path,
                        "lines": [start, end],
                        "sha256": hashlib.sha256(logical.encode("utf-8")).hexdigest(),
                        "text": logical,
                    },
                }
                for field, value in match.groupdict().items():
                    if value is not None:
                        effect[field] = value.strip()
                effects.append(effect)
        invocation = re.match(
            r"^(?P<function>[A-Za-z_][A-Za-z0-9_]*)\s+(?P<arguments>[^;&|]+?)\s*(?:;;)?$",
            flattened,
        )
        if invocation and invocation.group("function") in functions:
            effects.append({
                "type": "function-dispatch",
                "disposition": "unresolved-relationship",
                "function": invocation.group("function"),
                "arguments": invocation.group("arguments").strip(),
                "evidence": {
                    "source": source_path,
                    "lines": [start, end],
                    "sha256": hashlib.sha256(logical.encode("utf-8")).hexdigest(),
                    "text": logical,
                },
            })
    return effects


def account_donor_script(source_path: str, text: str) -> dict[str, Any]:
    """Account for every donor line without deciding that unknown shell is safe."""
    hunks: list[dict[str, Any]] = []
    for number, raw in enumerate(text.splitlines(), 1):
        stripped = raw.strip()
        if not stripped:
            classification, disposition = "blank", "evidence"
        elif number == 1 and stripped.startswith("#!"):
            classification, disposition = "interpreter", "translated"
        elif stripped.startswith("#"):
            classification, disposition = "comment", "evidence"
        elif DONOR_PROTOCOL.search(stripped):
            classification, disposition = "donor-protocol", "requires-translation"
        elif PORTABLE_EFFECT.search(stripped):
            classification, disposition = "portable-side-effect", "preserve"
        elif SHELL_CONTROL.search(stripped):
            classification, disposition = "shell-control", "preserve-with-body"
        else:
            classification, disposition = "shell-expression", "preserve-until-proven"
        hunk: dict[str, Any] = {
            "lines": [number, number],
            "classification": classification,
            "disposition": disposition,
            "text": raw,
        }
        effect = PORTABLE_EFFECT.search(stripped)
        if effect:
            hunk["operation"] = effect.group("command")
        hunks.append(hunk)
    return {
        "format": "auzix-donor-install-intake-v1",
        "source": source_path,
        "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "lines": len(text.splitlines()),
        "hunks": hunks,
        "effect_candidates": grok_donor_script(source_path, text),
    }


def write_donor_object(
    directory: Path, donor_name: str, source_path: str, text: str
) -> dict[str, Any]:
    directory.mkdir(parents=True, exist_ok=True)
    original = directory / f"{donor_name}.original"
    object_path = directory / f"{donor_name}.hunks.json"
    original.write_text(text, encoding="utf-8")
    accounted = account_donor_script(source_path, text)
    object_path.write_text(
        json.dumps(accounted, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return {
        "source": source_path,
        "original": str(original),
        "hunks": str(object_path),
        "sha256": accounted["sha256"],
        "lines": accounted["lines"],
        "effect_candidates": accounted["effect_candidates"],
    }
