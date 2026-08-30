from __future__ import annotations

import re
import hashlib


def apk_name(name: str) -> str:
    separated = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", name)
    separated = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1-\2", separated)
    return "auzix-" + separated.lower()


def apk_version(version: str) -> str:
    if re.fullmatch(r"\d+(?:\.\d+)*(?:-r\d+)?", version):
        return version if "-r" in version else version + "-r0"
    discriminator = int(hashlib.sha256(version.encode("utf-8")).hexdigest()[:8], 16)
    return f"0.{discriminator}-r0"
