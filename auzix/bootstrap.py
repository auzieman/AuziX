from __future__ import annotations

import hashlib
import shutil
import tempfile
import urllib.request
from pathlib import Path

from .contracts import ContractError
from .process import run


def bootstrap_apk_tools(package: dict, staged_root: Path) -> Path:
    source = package["source"]
    expected = source["sha256"]
    staged_root = staged_root.resolve()
    destination = staged_root / "Programs/ApkTools" / package["version"] / "Commands"
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="auzix-apk-bootstrap-") as temporary:
        archive = Path(temporary) / "apk-tools-static.apk"
        digest = hashlib.sha256()
        with urllib.request.urlopen(source["url"]) as response, archive.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
                output.write(chunk)
        if digest.hexdigest() != expected:
            raise ContractError(f"apk-tools bootstrap checksum mismatch: {digest.hexdigest()} != {expected}")
        extracted = Path(temporary) / "extracted"
        extracted.mkdir()
        run(["tar", "--ignore-zeros", "-xzf", str(archive), "-C", str(extracted)])
        binary = extracted / "sbin/apk.static"
        if not binary.is_file():
            raise ContractError("verified apk-tools archive does not contain sbin/apk.static")
        installed = destination / "apk"
        shutil.copy2(binary, installed)
        installed.chmod(0o755)
    current = staged_root / "Programs/ApkTools/current"
    if current.exists() or current.is_symlink():
        current.unlink()
    current.symlink_to(package["version"])
    return installed
