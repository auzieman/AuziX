from __future__ import annotations

import os
import shlex
import shutil
from pathlib import Path
from typing import Any

from .contracts import ContractError
from .process import run


def _render_argv(argv: list[str], staging_root: Path) -> list[str]:
    return [item.replace("${staging_root}", str(staging_root)) for item in argv]


def _stage_generated_layout(source: dict[str, Any], staging_root: Path) -> None:
    for absolute in source.get("directories", []):
        path = staging_root / absolute.lstrip("/")
        path.mkdir(parents=True, exist_ok=True)
        os.chmod(path, 0o755)
    for absolute, target in source.get("links", {}).items():
        path = staging_root / absolute.lstrip("/")
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() or path.is_symlink():
            raise ContractError(f"generated layout path already exists: {absolute}")
        path.symlink_to(target)


def stage_package(package: dict[str, Any], staging_root: Path, *, clean: bool = True) -> list[str]:
    staging_root = staging_root.resolve()
    if clean and staging_root.exists():
        shutil.rmtree(staging_root)
    staging_root.mkdir(parents=True, exist_ok=True)
    source = package["source"]
    if source["kind"] == "generated-layout":
        _stage_generated_layout(source, staging_root)
        return ["generated-layout", str(staging_root)]
    producer_argv = source.get("producer_argv")
    if not isinstance(producer_argv, list) or not producer_argv:
        raise ContractError(
            f"{package['name']}: source has no producer_argv; refusing an anonymous pre-staged payload"
        )
    argv = _render_argv(producer_argv, staging_root)
    run(argv)
    if not any(staging_root.iterdir()):
        raise ContractError(f"{package['name']}: producer emitted an empty staging root: {shlex.join(argv)}")
    return argv
