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
    }
